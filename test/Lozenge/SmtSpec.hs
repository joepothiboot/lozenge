{-# LANGUAGE OverloadedStrings #-}

module Lozenge.SmtSpec (tests) where

import Data.List (isInfixOf, isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import GHC.TypeNats (withSomeSNat)
import Golden (goldenText)
import Lozenge.Expr (BinOp (..), CmpOp (..), Expr (..), UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.Rule
import Lozenge.Smt
import Lozenge.Typed
import Props (props)
import System.Process (readProcessWithExitCode)
import TExprGen (genRule)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (counterexample, forAll, testProperty)
import Z3 (requireZ3)

tests :: TestTree
tests =
  testGroup
    "Smt"
    [ testGroup
        "smtName"
        [ testCase "x" $ smtName "x" @?= "v_x",
          testCase "a builtin name" $ smtName "and" @?= "v_and",
          testCase "a reserved word" $ smtName "_" @?= "v__"
        ],
      testGroup "toSmt" (width8 ++ width64),
      testGroup "ruleQuery golden" [goldenText (name r) (goldenFile r) (query r) | (r, _) <- goldens],
      testGroup
        "ruleQuery"
        [ testCase "no variables: no get-value" $
            ruleQuery (rule "no-vars" [] (Cmp Ult (bv 8 1) (bv 8 2)) (Lit (U.VBool True)))
              @?= Right
                ( T.unlines
                    [ "(set-option :produce-models true)",
                      "(set-logic QF_BV)",
                      "(assert (not (= (bvult (_ bv1 8) (_ bv2 8)) true)))",
                      "(check-sat)"
                    ]
                ),
          testCase "an unused variable is still declared" $
            fmap (T.isInfixOf "(declare-const v_y (_ BitVec 8))") (ruleQuery (rule "unused" bv8xy x x)) @?= Right True,
          rejects "lhs Bool, rhs BV" (rule "sorts" bv8xy (Cmp Ult x y) x),
          rejects "precondition is not Bool" (rule "pre" bv8x x x){rulePre = Just x},
          rejects "ill-typed lhs" (rule "ill" bv8x (Bin Add x (bv 16 0)) x),
          rejects "undeclared variable" (rule "unbound" bv8x (Var "z") x)
        ],
      props $
        testProperty "every query is balanced, one command per line" $
          forAll genRule $ \r -> case ruleQuery r of
            Left msg -> counterexample ("well-typed rule rejected: " <> T.unpack msg) False
            Right q -> counterexample (T.unpack q) (all balanced (T.lines q)),
      testGroup "z3 accepts every golden query" [z3Says r verdict | (r, verdict) <- goldens]
    ]

-- Each toSmt case is named by its expected output.
toSmtCase :: Text -> TExpr t -> TestTree
toSmtCase expected e = testCase (T.unpack expected) (toSmt e @?= expected)

width8 :: [TestTree]
width8 = withSomeSNat 8 $ \w ->
  let tx = TVar (SBV w) "x"
      ty = TVar (SBV w) "y"
      tp = TVar SBool "p"
      c = TLit . VBV w
   in [ toSmtCase "v_x" tx,
        toSmtCase "v_p" tp,
        toSmtCase "true" (TLit (VBool True)),
        toSmtCase "false" (TLit (VBool False)),
        toSmtCase "(_ bv0 8)" (c 0),
        toSmtCase "(_ bv255 8)" (c 255),
        toSmtCase "(bvnot v_x)" (TUn Not tx),
        toSmtCase "(bvneg v_x)" (TUn Neg tx),
        toSmtCase "(bvadd v_x v_y)" (TBin Add tx ty),
        toSmtCase "(bvsub v_x v_y)" (TBin Sub tx ty),
        toSmtCase "(bvmul v_x v_y)" (TBin Mul tx ty),
        toSmtCase "(bvand v_x v_y)" (TBin And tx ty),
        toSmtCase "(bvor v_x v_y)" (TBin Or tx ty),
        toSmtCase "(bvxor v_x v_y)" (TBin Xor tx ty),
        toSmtCase "(bvshl v_x v_y)" (TBin Shl tx ty),
        toSmtCase "(bvlshr v_x v_y)" (TBin Lshr tx ty),
        toSmtCase "(= v_x v_y)" (TCmp Eq tx ty),
        toSmtCase "(bvult v_x v_y)" (TCmp Ult tx ty),
        toSmtCase "(bvslt v_x v_y)" (TCmp Slt tx ty),
        toSmtCase "(ite v_p v_x (_ bv0 8))" (TIte tp tx (c 0)),
        toSmtCase
          "(ite (bvult v_x v_y) (bvadd (bvmul v_x v_y) (bvnot (_ bv1 8))) (bvneg v_y))"
          (TIte (TCmp Ult tx ty) (TBin Add (TBin Mul tx ty) (TUn Not (c 1))) (TUn Neg ty))
      ]

width64 :: [TestTree]
width64 = withSomeSNat 64 $ \w ->
  [toSmtCase "(_ bv18446744073709551615 64)" (TLit (VBV w (2 ^ (64 :: Int) - 1)))]

-- The golden rules, each with z3's answer: unsat when the rule is valid.
goldens :: [(Rule, String)]
goldens =
  [ (generic (rule "add-zero" bv8x (Bin Add x (bv 8 0)) x), "unsat"),
    (generic (rule "sub-comm" bv8xy (Bin Sub x y) (Bin Sub y x)), "sat"),
    (rule "ult-self" bv8x (Cmp Ult x x) (Lit (U.VBool False)), "unsat"),
    (generic (rule "ult-to-slt" bv8xy (Cmp Ult x y) (Cmp Slt x y)), "sat"),
    (generic (rule "ite-same" [("p", TBool), ("x", TBV 8)] (Ite (Var "p") x x) x), "unsat"),
    ( (rule "shl-lshr" [("x", TBV 4)] (Bin Lshr (Bin Shl x (bv 4 1)) (bv 4 1)) x)
        { rulePre = Just (Cmp Ult x (bv 4 8))
        },
      "unsat"
    ),
    ( (generic (rule "sub-zero-weak-pre" bv8xy (Bin Sub x y) (bv 8 0)))
        { rulePre = Just (Cmp Ult x (Bin Add y (bv 8 1)))
        },
      "sat"
    ),
    -- Unsanitised, z3 rejects both declarations.
    ( generic
        ( rule
            "de-morgan-awkward-names"
            [("_", TBV 8), ("and", TBV 8)]
            (Un Not (Bin And (Var "_") (Var "and")))
            (Bin Or (Un Not (Var "_")) (Un Not (Var "and")))
        ),
      "unsat"
    )
  ]

name :: Rule -> String
name = T.unpack . ruleName

goldenFile :: Rule -> FilePath
goldenFile r = "smt/" <> name r <> ".smt2"

query :: Rule -> IO Text
query r = either (fail . T.unpack) pure (ruleQuery r)

-- Runs z3 on the golden file, so this checks the spec even before ruleQuery
-- exists. After unsat, z3 reports that get-value has no model; that error is
-- expected and is the only one allowed.
z3Says :: Rule -> String -> TestTree
z3Says r verdict = requireZ3 (name r <> " is " <> verdict) $ do
  (_, out, err) <- readProcessWithExitCode "z3" ["test/golden/" <> goldenFile r] ""
  let allowed l = not ("(error" `isPrefixOf` l) || (verdict == "unsat" && "model is not available" `isInfixOf` l)
  case lines out of
    v : rest | v == verdict, all allowed rest -> pure out
    _ -> fail ("expected " <> verdict <> ", z3 said:\n" <> out <> err)

balanced :: Text -> Bool
balanced = go (0 :: Int) . T.unpack
  where
    go d [] = d == 0
    go d ('(' : cs) = go (d + 1) cs
    go d (')' : cs) = d > 0 && go (d - 1) cs
    go d (_ : cs) = go d cs

rejects :: String -> Rule -> TestTree
rejects label r = testCase label $ case ruleQuery r of
  Left _ -> pure ()
  Right q -> assertBool ("expected Left, got:\n" <> T.unpack q) False

rule :: Text -> [(Text, Ty)] -> Expr -> Expr -> Rule
rule n vars lhs rhs = Rule n Fixed (Map.fromList vars) lhs rhs Nothing

generic :: Rule -> Rule
generic r = r{ruleWidth = Generic}

bv :: Int -> Integer -> Expr
bv w v = Lit (U.VBV w v)

x, y :: Expr
x = Var "x"
y = Var "y"

bv8x, bv8xy :: [(Text, Ty)]
bv8x = [("x", TBV 8)]
bv8xy = [("x", TBV 8), ("y", TBV 8)]
