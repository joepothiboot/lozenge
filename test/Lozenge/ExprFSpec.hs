{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.ExprFSpec (tests) where

import Data.Foldable (toList)
import Data.Functor.Identity (Identity (..))
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import ExprGen (genExpr)
import GHC.TypeLits (SNat, natSing)
import Lozenge.CorpusSpec (loadCorpus)
import Lozenge.Expr (BinOp (..), CmpOp (..), Expr (..), UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.ExprF
import Lozenge.Fix
import Lozenge.Rule (Rule (..), RuleWidth (..))
import Lozenge.Typecheck (TypeError (..), typecheck)
import Lozenge.Typed
import Props (props)
import TExprGen (WellTyped (..), genRule, genWellTyped, testContext)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, arbitraryBoundedEnum, choose, counterexample, elements, forAll, oneof, property, sized, testProperty)

tests :: TestTree
tests =
  testGroup
    "ExprF"
    [ testGroup
        "derived instances"
        [ testCase "traverse Identity is Identity" $ mapM_ (\l -> traverse Identity l @?= Identity l) layers,
          testCase "fmap id is id" $ mapM_ (\l -> fmap id l @?= l) layers,
          testCase "ite folds condition, then, else" $ toList (IteF 1 2 3 :: ExprF Int) @?= [1, 2, 3],
          testCase "a leaf has no children" $ map length (filter isLeaf layers) @?= [0, 0, 0],
          testCase "traverse runs effects left to right" $
            traverse (\n -> ([n], n * 10)) (BinF Sub 1 2 :: ExprF Int) @?= ([1, 2], BinF Sub 10 20),
          testCase "Ord tells a term variable from a pattern variable" $
            compare (VarF "x" :: ExprF ()) (PVar "x") /= EQ @?= True
        ],
      testGroup
        "Fix"
        [ testCase "cata folds bottom-up" $ cata sizeAlg sample @?= 4,
          testCase "ana unfolds a seed" $ ana countdown (3 :: Int) @?= un Neg (un Neg (un Neg (v "x"))),
          testCase "para sees the original children" $
            para subtermsAlg sample @?= [sample, pv "x", un Neg (v "y"), v "y"],
          props $ testProperty "cata Fix = id" $ forAll genFix $ \t -> cata Fix t == t,
          props $ testProperty "ana unwrap = id" $ forAll genFix $ \t -> ana (\(Fix l) -> l) t == t,
          props $
            testProperty "para ignoring originals is cata" $
              forAll genFix $
                \t -> para (sizeAlg . fmap snd) t == cata sizeAlg t
        ],
      testGroup
        "size, depth, vars"
        [ testCase "size" $ size sample @?= 4,
          testCase "depth" $ depth sample @?= 3,
          testCase "a leaf has depth 1" $ depth (v "x") @?= 1,
          testCase "vars has both kinds" $ vars sample @?= Set.fromList ["x", "y"],
          testCase "a literal has no vars" $ vars (lit (U.VBV 8 0)) @?= Set.empty,
          props $ testProperty "size equals the hand-written size" $ forAll genFix $ \t -> size t == handSize t,
          props $ testProperty "depth equals the hand-written depth" $ forAll genFix $ \t -> depth t == handDepth t,
          props $ testProperty "vars equals the hand-written vars" $ forAll genFix $ \t -> vars t == handVars t
        ],
      testGroup
        "fromTyped"
        [ testCase "variables and a literal" $
            fromTyped (TBin Add tx (TLit (VBV w8 3))) @?= bin Add (v "x") (lit (U.VBV 8 3)),
          testCase "Bool literal, comparison, ite" $
            fromTyped (TIte (TCmp Ult tx tx) (TLit (VBV w8 0)) tx)
              @?= Fix (IteF (Fix (CmpF Ult (v "x") (v "x"))) (lit (U.VBV 8 0)) (v "x")),
          testCase "a Bool variable" $ fromTyped (TVar SBool "p") @?= v "p",
          testCase "the widest literal" $
            fromTyped (TLit (VBV (natSing @64) (2 ^ (64 :: Int) - 1))) @?= lit (U.VBV 64 (2 ^ (64 :: Int) - 1)),
          props $
            testProperty "never makes a PVar" $
              forAll genWellTyped $
                \(WellTyped _ (SomeExpr _ te) _) -> noPVar (fromTyped te)
        ],
      testGroup
        "toTyped"
        [ props $
            testProperty "toTyped . fromTyped is the identity on well-typed terms" $
              forAll genWellTyped $ \(WellTyped ctx se@(SomeExpr _ te) _) ->
                let got = show (toTyped ctx (fromTyped te))
                 in counterexample got (got == show (Right se :: Either TypeError SomeExpr)),
          props $
            testProperty "same answer as typecheck, errors included" $
              forAll genExpr $ \e ->
                let got = show (toTyped testContext (fromExpr e))
                    want = show (typecheck testContext e)
                 in counterexample ("toTyped:   " <> got <> "\ntypecheck: " <> want) (got == want),
          testCase "a PVar is typed as its variable" $
            show (toTyped testContext (pv "x")) @?= show (Right (SomeExpr (SBV w8) tx) :: Either TypeError SomeExpr),
          testCase "an unbound PVar" $ show (toTyped testContext (pv "w")) @?= show (Left (UnboundVar "w") :: Either TypeError SomeExpr)
        ],
      testGroup
        "ruleToFix"
        [ testCase "add-zero" $
            ruleToFix addZero
              @?= Right
                FixRule
                  { frName = "add-zero",
                    frWidth = Generic,
                    frVars = Map.fromList [("x", TBV 8)],
                    frLhs = bin Add (pv "x") (lit (U.VBV 8 0)),
                    frRhs = pv "x",
                    frPre = Nothing
                  },
          testCase "the precondition is converted too" $
            fmap frPre (ruleToFix addZero{rulePre = Just (Cmp Ult x (bv 8 8))})
              @?= Right (Just (Fix (CmpF Ult (pv "x") (lit (U.VBV 8 8))))),
          rejects "ill-typed lhs" addZero{ruleLhs = Bin Add x (bv 16 0)},
          rejects "lhs BV, rhs Bool" addZero{ruleRhs = Lit (U.VBool True)},
          rejects "lhs and rhs widths differ" addZero{ruleVars = Map.fromList [("x", TBV 8), ("y", TBV 16)], ruleRhs = Var "y"},
          rejects "precondition is not Bool" addZero{rulePre = Just x},
          props $
            testProperty "each side's toTyped agrees with typecheck" $
              forAll genRule $ \r -> case ruleToFix r of
                Left msg -> counterexample ("well-typed rule rejected: " <> show msg) False
                Right fr ->
                  let same e t = show (toTyped (frVars fr) t) == show (typecheck (ruleVars r) e)
                   in property (same (ruleLhs r) (frLhs fr) && same (ruleRhs r) (frRhs fr)),
          testCase "every corpus rule converts, with only pattern variables" $ do
            rules <- loadCorpus
            let bad = [(ruleName r, why) | r <- rules, Just why <- [corpusProblem r]]
            if null bad then pure () else assertFailure (unlines (map show bad))
        ]
    ]

-- Nothing if r converts to a FixRule with no VarF and no new variables.
corpusProblem :: Rule -> Maybe String
corpusProblem r = case ruleToFix r of
  Left msg -> Just (show msg)
  Right fr
    | not (all noVarF sides) -> Just "a VarF is left"
    | not (all ((`Set.isSubsetOf` Map.keysSet (ruleVars r)) . vars) sides) -> Just "a variable not in ruleVars"
    | otherwise -> Nothing
    where
      sides = frLhs fr : frRhs fr : toList (frPre fr)

rejects :: String -> Rule -> TestTree
rejects label r = testCase label $ case ruleToFix r of
  Left _ -> pure ()
  Right fr -> assertFailure ("expected Left, got " <> show fr)

-- One layer of each constructor.
layers :: [ExprF Int]
layers =
  [VarF "x", PVar "x", LitF (U.VBV 8 1), UnF Neg 1, BinF Add 1 2, CmpF Eq 1 2, IteF 1 2 3]

isLeaf :: ExprF r -> Bool
isLeaf e = case e of
  VarF _ -> True
  PVar _ -> True
  LitF _ -> True
  _ -> False

-- (add ?x (neg y))
sample :: Fix ExprF
sample = bin Add (pv "x") (un Neg (v "y"))

sizeAlg :: ExprF Int -> Int
sizeAlg = (1 +) . sum

subtermsAlg :: ExprF (Fix ExprF, [Fix ExprF]) -> [Fix ExprF]
subtermsAlg l = Fix (fmap fst l) : concatMap snd l

countdown :: Int -> ExprF Int
countdown 0 = VarF "x"
countdown n = UnF Neg (n - 1)

handSize, handDepth :: Fix ExprF -> Int
handSize (Fix l) = 1 + sum (map handSize (children l))
handDepth (Fix l) = 1 + maximum (0 : map handDepth (children l))

handVars :: Fix ExprF -> Set.Set Text
handVars (Fix l) = case l of
  VarF n -> Set.singleton n
  PVar n -> Set.singleton n
  _ -> Set.unions (map handVars (children l))

children :: ExprF r -> [r]
children l = case l of
  VarF _ -> []
  PVar _ -> []
  LitF _ -> []
  UnF _ a -> [a]
  BinF _ a b -> [a, b]
  CmpF _ a b -> [a, b]
  IteF c a b -> [c, a, b]

noPVar, noVarF :: Fix ExprF -> Bool
noPVar (Fix l) = case l of
  PVar _ -> False
  _ -> all noPVar (children l)
noVarF (Fix l) = case l of
  VarF _ -> False
  _ -> all noVarF (children l)

fromExpr :: Expr -> Fix ExprF
fromExpr e = Fix $ case e of
  Var n -> VarF n
  Lit val -> LitF val
  Un op a -> UnF op (fromExpr a)
  Bin op a b -> BinF op (fromExpr a) (fromExpr b)
  Cmp op a b -> CmpF op (fromExpr a) (fromExpr b)
  Ite c a b -> IteF (fromExpr c) (fromExpr a) (fromExpr b)

genFix :: Gen (Fix ExprF)
genFix = sized go
  where
    go n
      | n <= 0 = leaf
      | otherwise =
          oneof
            [ leaf,
              un <$> arbitraryBoundedEnum <*> go (n - 1),
              bin <$> arbitraryBoundedEnum <*> go (n `div` 2) <*> go (n `div` 2),
              (\op a b -> Fix (CmpF op a b)) <$> arbitraryBoundedEnum <*> go (n `div` 2) <*> go (n `div` 2),
              (\c a b -> Fix (IteF c a b)) <$> go (n `div` 3) <*> go (n `div` 3) <*> go (n `div` 3)
            ]
    leaf =
      oneof
        [ v <$> elements ["x", "y"],
          pv <$> elements ["x", "y"],
          lit . U.VBV 8 <$> choose (0, 255),
          lit . U.VBool <$> elements [False, True]
        ]

addZero :: Rule
addZero = Rule "add-zero" Generic (Map.fromList [("x", TBV 8)]) (Bin Add x (bv 8 0)) x Nothing

x :: Expr
x = Var "x"

bv :: Int -> Integer -> Expr
bv w n = Lit (U.VBV w n)

v, pv :: Text -> Fix ExprF
v = Fix . VarF
pv = Fix . PVar

lit :: U.Value -> Fix ExprF
lit = Fix . LitF

un :: UnOp -> Fix ExprF -> Fix ExprF
un op = Fix . UnF op

bin :: BinOp -> Fix ExprF -> Fix ExprF -> Fix ExprF
bin op a b = Fix (BinF op a b)

w8 :: SNat 8
w8 = natSing

tx :: TExpr ('TBV 8)
tx = TVar (SBV w8) "x"
