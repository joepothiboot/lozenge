{-# LANGUAGE OverloadedStrings #-}

module Lozenge.RewriteSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Lozenge.Expr (BinOp (..), CmpOp (..), UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.ExprF (ExprF (..), FixRule (..))
import Lozenge.Fix (Fix (..))
import Lozenge.Rewrite
import Lozenge.Rule (RuleWidth (..))
import Lozenge.Typed (Ty (..))
import Props (props)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, checkCoverage, counterexample, cover, elements, forAll, frequency, property, testProperty, (.&&.), (===))

tests :: TestTree
tests =
  testGroup
    "Rewrite"
    [ testGroup
        "applySubst"
        [ testCase "replaces a bound PVar everywhere" $
            applySubst (sub [("x", neg a)]) (add px px) @?= add (neg a) (neg a),
          testCase "leaves VarF and unbound PVar" $
            applySubst (sub [("a", b), ("x", b)]) (add a py) @?= add a py,
          testCase "one pass" $ applySubst (sub [("x", py), ("y", a)]) px @?= py
        ],
      testGroup
        "match"
        [ testCase "binds every variable" $
            match (add px py) (add a (neg b)) @?= Just (sub [("x", a), ("y", neg b)]),
          testCase "a variable that would need two values" $ match (xor px px) (xor a b) @?= Nothing,
          testCase "a repeated variable with equal subterms" $
            match (xor px px) (xor (neg a) (neg a)) @?= Just (sub [("x", neg a)]),
          testCase "constants must agree" $ match (add px zero) (add a b) @?= Nothing,
          testCase "a VarF in the pattern is a constant" $ match (add a px) (add b b) @?= Nothing,
          testCase "a PVar in the subject is a constant" $ match (neg a) (neg px) @?= Nothing,
          testCase "a PVar matches a PVar" $ match px py @?= Just (sub [("x", py)]),
          testCase "literal widths must agree" $
            match (add px zero) (add a (Fix (LitF (U.VBV 16 0)))) @?= Nothing,
          testCase "operators must agree" $ match (add px py) (xor a b) @?= Nothing,
          props $
            testProperty "Just s: applySubst s p == t" $
              forAll (genTerm ["x", "y"]) $ \p -> forAll (genTerm []) $ \t ->
                maybe True (\s -> applySubst s p == t) (match p t),
          props $
            testProperty "matches every instance, binding exactly the pattern's variables" $
              forAll (genTerm ["x", "y", "z"]) $ \p -> forAll genGroundSubst $ \s ->
                let t = applySubst s p
                 in case match p t of
                      Nothing -> counterexample ("no match for " <> show t) False
                      Just s' -> applySubst s' p === t .&&. Map.keysSet s' === pvars p
        ],
      testGroup
        "unify"
        [ testCase "occurs check" $ unify px (neg px) @?= Nothing,
          testCase "occurs check through another variable" $ unify (add px py) (add py (neg px)) @?= Nothing,
          testCase "a variable with itself" $ unify px px @?= Just Map.empty,
          testCase "both sides bind" $ unify (add px b) (add a py) @?= Just (sub [("x", a), ("y", b)]),
          testCase "the result is idempotent" $ unify (add px py) (add py a) @?= Just (sub [("x", a), ("y", a)]),
          testCase "operators clash" $ unify (neg px) (add a b) @?= Nothing,
          testCase "VarFs clash" $ unify a b @?= Nothing,
          props $
            testProperty "Just s: applySubst s a == applySubst s b, and s is idempotent" $
              forAll ((,) <$> genTerm ["x", "y", "z"] <*> genTerm ["x", "y", "z"]) $ \(l, r) ->
                checkCoverage . cover 10 (isJust (unify l r)) "unifiable" $ case unify l r of
                  Nothing -> property True
                  Just s ->
                    applySubst s l
                      === applySubst s r
                      .&&. counterexample "not idempotent" (all (\t -> applySubst s t == t) (Map.elems s)),
          props $
            testProperty "most general, checked against every small ground unifier" $
              forAll ((,) <$> genSmall <*> genSmall) $ \(l, r) ->
                let unifiers = [u | u <- groundSubsts, applySubst u l == applySubst u r]
                 in case unify l r of
                      Nothing -> counterexample ("unify said Nothing, but this unifies: " <> show (take 1 unifiers)) (null unifiers)
                      Just s ->
                        counterexample "a ground unifier is not an instance of s" $
                          and [applySubst u (applySubst s (pv x)) == applySubst u (pv x) | u <- unifiers, x <- ["x", "y"]]
        ],
      testGroup
        "rewriteOnce"
        [ testCase "outermost: the root first" $
            rewriteOnce [notNot] (notE (notE (notE (notE a)))) @?= Just (notE (notE a)),
          testCase "leftmost: the left child before the right" $
            rewriteOnce [addZero] (add (add a zero) (add b zero)) @?= Just (add a (add b zero)),
          testCase "the whole left subtree before the right child" $
            rewriteOnce [addZero] (add (neg (add a zero)) (add b zero)) @?= Just (add (neg a) (add b zero)),
          testCase "rules in order at one position" $ do
            rewriteOnce [toA, addZero] (add b zero) @?= Just a
            rewriteOnce [addZero, toA] (add b zero) @?= Just b,
          testCase "position before rule order" $ rewriteOnce [negDrop, toA] (add (neg b) b) @?= Just a,
          testCase "a non-linear rule" $ do
            rewriteOnce [xorSelf] (xor (neg a) (neg a)) @?= Just zero
            rewriteOnce [xorSelf] (xor a b) @?= Nothing,
          testCase "a normal form" $ rewriteOnce [addZero, notNot] (add a b) @?= Nothing,
          testCase "a rule with a precondition is skipped" $ rewriteOnce [guarded] (add a zero) @?= Nothing
        ],
      testGroup
        "normalise"
        [ testCase "add-zero twice" $ normalise 10 [addZero] twice @?= ([], Done a),
          testCase "comm on (add a b) is a cycle" $
            normalise 10 [comm] (add a b) @?= ([], Cycle 2 [add a b, add b a, add a b]),
          testCase "a cycle that closes on the last step" $
            normalise 2 [comm] (add a b) @?= ([], Cycle 2 [add a b, add b a, add a b]),
          testCase "the repeat need not be the start" $
            normalise 10 [intoComm, comm] (notE a) @?= ([], Cycle 3 [notE a, add a b, add b a, add a b]),
          testCase "fuel 1 is too little for add-zero twice" $
            normalise 1 [addZero] twice @?= ([], OutOfFuel [twice, add a zero]),
          testCase "two terms of the same shape in a row are not a cycle" $
            normalise 10 [swapAB] (add a b) @?= ([], Done (add b a)),
          testCase "two terms that differ only in a literal are not a cycle" $
            normalise 10 [zeroToOne] (add a zero) @?= ([], Done (add a one)),
          testCase "fuel 2 is just enough" $ normalise 2 [addZero] twice @?= ([], Done a),
          testCase "fuel 0" $ do
            normalise 0 [addZero] a @?= ([], Done a)
            normalise 0 [addZero] twice @?= ([], OutOfFuel [twice])
            normalise (-1) [addZero] twice @?= ([], OutOfFuel [twice]),
          testCase "a growing term runs out of fuel" $
            normalise 3 [grow] (neg a) @?= ([], OutOfFuel (take 4 (iterate neg (neg a)))),
          testCase "a rule with a precondition is skipped and named" $
            normalise 10 [guarded, addZero, guarded{frName = "also-guarded"}] twice
              @?= (["guarded", "also-guarded"], Done a),
          props $
            testProperty "terminating rules: Done, and nothing applies" $
              forAll (genTerm []) $ \t -> case snd (normalise 100 terminating t) of
                Done u -> rewriteOnce terminating u === Nothing
                other -> counterexample (show other) False,
          props $
            testProperty "each term seen is rewriteOnce of the one before" $
              forAll (genTerm []) $ \t ->
                let rules = [comm, addZero, negNeg]
                    steps ts = and (zipWith (\u v -> rewriteOnce rules u == Just v) ts (drop 1 ts))
                 in case snd (normalise 6 rules t) of
                      Done u -> rewriteOnce rules u === Nothing
                      Cycle k ts -> length ts === k + 1 .&&. property (steps ts) .&&. property (last ts `elem` init ts)
                      OutOfFuel ts -> length ts === 7 .&&. property (steps ts) .&&. Set.size (Set.fromList ts) === 7
        ]
    ]

genTerm :: [Text] -> Gen (Fix ExprF)
genTerm vs = go (3 :: Int)
  where
    go d
      | d <= 0 = leaf
      | otherwise = frequency [(2, leaf), (1, neg <$> go (d - 1)), (2, add <$> go (d - 1) <*> go (d - 1))]
    leaf = elements ([a, b, zero] <> map pv vs)

genSmall :: Gen (Fix ExprF)
genSmall = go (2 :: Int)
  where
    go d
      | d <= 0 = leaf
      | otherwise = frequency [(2, leaf), (1, neg <$> go (d - 1)), (2, add <$> go (d - 1) <*> go (d - 1))]
    leaf = elements [a, b, zero, px, py]

genGroundSubst :: Gen Subst
genGroundSubst = Map.fromList . zip ["x", "y", "z"] <$> sequence [genTerm [], genTerm [], genTerm []]

groundSubsts :: [Subst]
groundSubsts = [sub [("x", s), ("y", t)] | s <- ground, t <- ground]
  where
    leaves = [a, b, zero]
    ground = leaves <> map neg leaves <> [add l r | l <- leaves, r <- leaves]

pvars :: Fix ExprF -> Set.Set Text
pvars (Fix l) = case l of
  PVar n -> Set.singleton n
  _ -> foldMap pvars l

sub :: [(Text, Fix ExprF)] -> Subst
sub = Map.fromList

rule :: Text -> Fix ExprF -> Fix ExprF -> FixRule
rule n l r = FixRule n Generic (Map.fromList [("x", TBV 8), ("y", TBV 8)]) l r Nothing

addZero, notNot, negNeg, negDrop, xorSelf, comm, toA, intoComm, grow, guarded, swapAB, zeroToOne :: FixRule
addZero = rule "add-zero" (add px zero) px
notNot = rule "not-not" (notE (notE px)) px
negNeg = rule "neg-neg" (neg (neg px)) px
negDrop = rule "neg-drop" (neg px) px
xorSelf = rule "xor-self" (xor px px) zero
comm = rule "comm" (add px py) (add py px)
toA = rule "to-a" (add px py) a
intoComm = rule "into-comm" (notE a) (add a b)
grow = rule "grow" (neg px) (neg (neg px))
guarded = (rule "guarded" (add px zero) px){frPre = Just (Fix (CmpF Ult px zero))}
swapAB = rule "swap-a-b" (add a b) (add b a)
zeroToOne = rule "zero-to-one" (add a zero) (add a one)

terminating :: [FixRule]
terminating = [addZero, negNeg]

twice :: Fix ExprF
twice = add (add a zero) zero

a, b, zero, one, px, py :: Fix ExprF
a = Fix (VarF "a")
b = Fix (VarF "b")
zero = Fix (LitF (U.VBV 8 0))
one = Fix (LitF (U.VBV 8 1))
px = pv "x"
py = pv "y"

pv :: Text -> Fix ExprF
pv = Fix . PVar

neg, notE :: Fix ExprF -> Fix ExprF
neg = Fix . UnF Neg
notE = Fix . UnF Not

add, xor :: Fix ExprF -> Fix ExprF -> Fix ExprF
add l r = Fix (BinF Add l r)
xor l r = Fix (BinF Xor l r)
