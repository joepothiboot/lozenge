{-# LANGUAGE OverloadedStrings #-}

module Lozenge.VerifySmtSpec (tests) where

import Control.Monad (unless)
import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Traversable (for)
import Lozenge.CorpusSpec (loadCorpus)
import Lozenge.EvalT (checkEnv, evalT)
import Lozenge.Expr
import Lozenge.Rule
import Lozenge.Typecheck (typecheck)
import Lozenge.Typed (SomeExpr (..), Ty (..))
import Lozenge.VerifyBrute (Assignment, Verdict (..), verifyBrute)
import Lozenge.VerifySmt
import TExprGen (untyped)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))
import Z3 (requireZ3)

tests :: TestTree
tests =
  testGroup
    "VerifySmt"
    [ testGroup
        "runVerify"
        [ testCase "pure" $ runVerify (cfg 8) (pure 'a') >>= (@?= Right 'a'),
          testCase "asks reads the config" $ runVerify (cfg 5) (asks configWidth) >>= (@?= Right 5),
          testCase "throwError" $
            runVerify (cfg 8) (throwError (SolverFailed "boom") :: Verify ()) >>= (@?= Left (SolverFailed "boom")),
          testCase "liftIO" $ runVerify (cfg 8) (liftIO (pure (3 :: Int))) >>= (@?= Right 3)
        ],
      testGroup
        "toAssignment"
        [ testCase "BV and Bool, extra symbols ignored" $
            toAssignment ctx (Map.fromList [("v_p", 1), ("v_x", 200), ("v_q", 0), ("other", 7)])
              @?= Right (Map.fromList [("p", VBool True), ("q", VBool False), ("x", VBV 8 200)]),
          testCase "a missing variable" $ isLeft (toAssignment ctx (Map.fromList [("v_p", 1), ("v_q", 0)])),
          testCase "a BV value too wide" $ isLeft (toAssignment ctx (Map.fromList [("v_p", 1), ("v_q", 0), ("v_x", 256)])),
          testCase "a Bool value other than 0 or 1" $
            isLeft (toAssignment ctx (Map.fromList [("v_p", 2), ("v_q", 0), ("v_x", 0)]))
        ],
      testGroup
        "Unsupported before z3"
        [ unsupported "ill-typed lhs" 8 (rule "ill" Fixed bv8xy (Bin Add x (bv 16 0)) x),
          unsupported "Generic at width 0" 0 addComm,
          unsupported "Generic at width 65" 65 addComm
        ],
      testGroup "corpus: brute force and SMT agree" [corpusAgrees w | w <- [1 .. 6]],
      testGroup
        "beyond brute force"
        [ requireZ3 "add-comm at width 32 is valid" $ do
            bruteGivesUp 32 addComm
            runVerify (cfg 32) (verifySmt addComm) >>= (@?= Right Valid)
            pure "",
          requireZ3 "ult-to-slt at width 32 has a real counterexample" $ do
            bruteGivesUp 32 ultToSlt
            r <- runVerify (cfg 32) (verifySmt ultToSlt)
            case r of
              Right v@(Counterexample a _ _) -> either assertFailure pure (confirm 32 ultToSlt v a)
              other -> assertFailure ("expected a counterexample, got " <> show other)
            pure ""
        ]
    ]

corpusAgrees :: Int -> TestTree
corpusAgrees w = requireZ3 ("width " <> show w) $ do
  rules <- loadCorpus
  problems <- fmap catMaybes . for rules $ \r ->
    disagreement w r (verifyBrute w r) <$> runVerify (cfg w) (verifySmt r)
  unless (null problems) $ assertFailure (unlines problems)
  pure (show (length rules) <> " rules agree")

disagreement :: Int -> Rule -> Verdict -> Either VerifyError Verdict -> Maybe String
disagreement w r brute smt = case (brute, smt) of
  (Valid, Right Valid) -> Nothing
  (Unsupported _, Right (Unsupported _)) -> Nothing
  (Counterexample{}, Right v@(Counterexample a _ _)) -> either (Just . here) (const Nothing) (confirm w r v a)
  (Valid, Right v@(Counterexample a _ _)) -> Just . here $ case confirm w r v a of
    Right () ->
      "z3 found "
        <> show a
        <> " and evalT confirms it, but brute force said Valid. "
        <> "Suspect verifyBrute first: an assignment never tried, or the precondition handled wrongly."
    Left why -> why
  (Counterexample a _ _, Right Valid) ->
    Just . here $
      "brute force found " <> show a <> ", but z3 says no counterexample exists. " <> emitterFirst
  (_, Left (SpuriousCounterexample a)) -> Just (here (spurious a))
  (_, Left (SolverFailed m)) ->
    Just . here $
      "z3 failed: " <> T.unpack m <> ". Suspect the emitter first: does z3 accept the query? Run -p Smt."
  (_, Right s) ->
    Just . here $
      "brute force says "
        <> show brute
        <> ", SMT says "
        <> show s
        <> ". "
        <> "At widths 1-6 every corpus rule is within the brute-force cap, so suspect the side that "
        <> "said Unsupported: its instantiate or typecheck step."
  where
    here msg = T.unpack (ruleName r) <> " @" <> show w <> ": " <> msg

confirm :: Int -> Rule -> Verdict -> Assignment -> Either String ()
confirm w r verdict a = do
  (holds, l, rh) <- evalAt w r a
  unless holds $ Left (spurious a <> " (the precondition is false there)")
  unless (l /= rh) $ Left (spurious a <> " (lhs and rhs are both " <> show l <> ")")
  unless (verdict == Counterexample a l rh) $
    Left ("verifySmt reported " <> show verdict <> ", but evalT gives lhs = " <> show l <> ", rhs = " <> show rh <> ". Suspect verifySmt's evaluation step.")

spurious :: Assignment -> String
spurious a = "z3 says " <> show a <> " breaks the rule, but evalT says it does not. " <> emitterFirst

emitterFirst :: String
emitterFirst =
  "Suspect the emitter first (an operator mapped to the wrong SMT-LIB function, a missing or extra "
    <> "assert): it is the newest code and only 8 goldens check it. Then evaluate the rule at that "
    <> "assignment by hand with docs/SEMANTICS.md: if your answer differs from evalT, evalT is wrong; "
    <> "if it matches evalT, compare SEMANTICS.md's SMT-LIB column with the SMT-LIB standard."

-- (precondition holds, lhs, rhs) at an assignment, by evalT.
evalAt :: Int -> Rule -> Assignment -> Either String (Bool, Value, Value)
evalAt w r a = do
  r' <- maybe (Left "instantiate gave Nothing") Right (instantiate w r)
  tenv <- first show (checkEnv (ruleVars r') a)
  let value e = do
        SomeExpr _ te <- first show (typecheck (ruleVars r') e)
        pure (untyped (evalT tenv te))
  pre <- maybe (Right (VBool True)) value (rulePre r')
  (,,) (pre == VBool True) <$> value (ruleLhs r') <*> value (ruleRhs r')

bruteGivesUp :: Int -> Rule -> IO ()
bruteGivesUp w r = case verifyBrute w r of
  Unsupported _ -> pure ()
  other -> assertFailure ("expected brute force to give up, got " <> show other)

unsupported :: String -> Int -> Rule -> TestTree
unsupported name w r = testCase name $ do
  v <- runVerify (cfg w) (verifySmt r)
  case v of
    Right (Unsupported _) -> pure ()
    other -> assertFailure ("expected Right (Unsupported _), got " <> show other)

isLeft :: (Show a) => Either Text a -> IO ()
isLeft (Left _) = pure ()
isLeft (Right v) = assertFailure ("expected Left, got " <> show v)

cfg :: Int -> Config
cfg w = Config{configWidth = w, configTimeoutMs = 10000}

ctx :: Map.Map Text Ty
ctx = Map.fromList [("p", TBool), ("q", TBool), ("x", TBV 8)]

rule :: Text -> RuleWidth -> [(Text, Ty)] -> Expr -> Expr -> Rule
rule name w vars lhs rhs = Rule name w (Map.fromList vars) lhs rhs Nothing

bv :: Int -> Integer -> Expr
bv w v = Lit (VBV w v)

x, y :: Expr
x = Var "x"
y = Var "y"

bv8xy :: [(Text, Ty)]
bv8xy = [("x", TBV 8), ("y", TBV 8)]

addComm, ultToSlt :: Rule
addComm = rule "add-comm" Generic bv8xy (Bin Add x y) (Bin Add y x)
ultToSlt = rule "ult-to-slt" Generic bv8xy (Cmp Ult x y) (Cmp Slt x y)
