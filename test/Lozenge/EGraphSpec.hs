-- Variable names in terms are Text.
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.EGraphSpec (tests) where

import Control.Monad (foldM, forM, replicateM, unless)
import Control.Monad.ST (ST, runST)
import Data.Foldable (toList)
import Data.Functor (void)
import Data.List (nub, partition, sortOn)
import Data.Text (Text)
import Lozenge.EGraph
import Lozenge.Expr (BinOp (..), UnOp (..), Value (..))
import Lozenge.ExprF (ExprF (..))
import Lozenge.Fix (Fix (..))
import Props (props)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, Property, checkCoverage, chooseInt, conjoin, counterexample, cover, elements, forAllShrinkShow, frequency, shrink, shrinkList, sized, testProperty, (===))

tests :: TestTree
tests =
  testGroup
    "EGraph"
    [ testGroup
        "addTerm and addNode"
        [ testCase "the same term twice gives the same id" $
            withGraph (\g -> (==) <$> addTerm g (f (f a)) <*> addTerm g (f (f a))) @?= True,
          testCase "different terms are different classes" $
            withGraph (\g -> do x <- addTerm g a; y <- addTerm g b; z <- addTerm g (f a); sequence [equiv g x y, equiv g x z]) @?= [False, False],
          testCase "the operator is part of the node: neg a and not a differ" $
            withGraph (\g -> do x <- addTerm g (f a); y <- addTerm g (h a); equiv g x y) @?= False,
          testCase "subterms are shared: addNode finds (add a a) from a's id" $
            withGraph (\g -> do s <- addTerm g (add a a); x <- addTerm g a; s' <- addNode g (BinF Add x x); pure (s == s')) @?= True
        ],
      testGroup
        "merge and rebuild"
        [ testCase "merge makes the two ids equivalent at once" $
            withGraph (\g -> do x <- addTerm g a; y <- addTerm g b; merge g x y; equiv g x y) @?= True,
          testCase "merge a b, then rebuild: f(a) and f(b) are equivalent" $
            withGraph (\g -> do (x, y, fx, fy) <- abfafb g; merge g x y; rebuild g; equiv g fx fy) @?= True,
          testCase "before rebuild, f(a) and f(b) are still two classes" $
            withGraph (\g -> do (x, y, fx, fy) <- abfafb g; merge g x y; equiv g fx fy) @?= False,
          testCase "congruence climbs: merge a b gives f(f(a)) = f(f(b))" $
            withGraph (\g -> do ffa <- addTerm g (f (f a)); ffb <- addTerm g (f (f b)); x <- addTerm g a; y <- addTerm g b; merge g x y; rebuild g; equiv g ffa ffb) @?= True,
          testCase "no over-merging: merge a b leaves f(a) and f(c) apart" $
            withGraph (\g -> do (x, y, fx, _) <- abfafb g; fz <- addTerm g (f c); merge g x y; rebuild g; equiv g fx fz) @?= False,
          testCase "addNode canonicalises children: neg of b's old id finds f(a)'s class" $
            withGraph (\g -> do (x, y, _, _) <- abfafb g; merge g x y; rebuild g; n <- addNode g (UnF Neg y); m <- addTerm g (f a); pure (n == m)) @?= True,
          testCase "merging a class with itself changes nothing" $
            withGraph (\g -> do (x, _, _, _) <- abfafb g; merge g x x; checkInvariants g) @?= []
        ],
      testGroup
        "checkInvariants"
        [ testCase "an empty graph has no violations" $ withGraph checkInvariants @?= [],
          testCase "adding terms keeps the invariants" $
            withGraph (\g -> mapM_ (addTerm g) [add (f a) (f b), f (f a), add a a] >> checkInvariants g) @?= [],
          testCase "merge a b without rebuild: f(a), f(b) break congruence and are reported" $ do
            let vs = withGraph (\g -> do (x, y, _, _) <- abfafb g; merge g x y; checkInvariants g)
            assertBool "expected at least one violation" (not (null vs)),
          testCase "rebuild clears them" $
            withGraph (\g -> do (x, y, _, _) <- abfafb g; merge g x y; rebuild g; checkInvariants g) @?= []
        ],
      testGroup
        "classes"
        [ testCase "each class once, by ascending id, with its nodes" $
            withGraph
              ( \g -> do
                  s <- addTerm g (add a a)
                  x <- addTerm g a
                  cs <- classes g
                  pure (cs == sortOn fst [(x, [VarF "a"]), (s, [BinF Add x x])])
              )
              @?= True,
          testCase "after merge a b and rebuild: one class with a and b, and f(a), f(b) as one node" $
            withGraph
              ( \g -> do
                  (x, y, _, _) <- abfafb g
                  merge g x y
                  rebuild g
                  r <- addTerm g a
                  fr <- addTerm g (f a)
                  cs <- classes g
                  pure (cs == sortOn fst [(r, [VarF "a", VarF "b"]), (fr, [UnF Neg r])])
              )
              @?= True
        ],
      testGroup
        "congruence closure"
        [ testCase "f(f(f(a))) = a and f(f(a)) = a imply f(a) = a" $
            withGraph
              ( \g -> do
                  x <- addTerm g a
                  f3 <- addTerm g (f (f (f a)))
                  merge g f3 x
                  rebuild g
                  f2 <- addTerm g (f (f a))
                  merge g f2 x
                  rebuild g
                  f1 <- addTerm g (f a)
                  y <- addTerm g b
                  (,,) <$> equiv g f1 x <*> equiv g y x <*> checkInvariants g
              )
              @?= (True, False, []),
          testCase "the same, with both merges before one rebuild" $
            withGraph
              ( \g -> do
                  x <- addTerm g a
                  f3 <- addTerm g (f (f (f a)))
                  f2 <- addTerm g (f (f a))
                  merge g f3 x
                  merge g f2 x
                  rebuild g
                  f1 <- addTerm g (f a)
                  equiv g f1 x
              )
              @?= True
        ],
      testGroup
        "random programs"
        [ props $
            testProperty "checkInvariants is [] after every rebuild" $
              forAllShrinkShow genOps shrinkOps show $ \ops ->
                let (checks, _) = runProgram ops
                 in conjoin [counterexample ("rebuild number " <> show i) (vs === []) | (i, vs) <- zip [1 :: Int ..] checks],
          props
            $ testProperty "equiv agrees with a naive congruence closure"
            $ forAllShrinkShow genOps shrinkOps show (checkCoverage . agrees)
        ]
    ]

type Term = Fix ExprF

a, b, c :: Term
a = Fix (VarF "a")
b = Fix (VarF "b")
c = Fix (VarF "c")

f, h :: Term -> Term
f = Fix . UnF Neg
h = Fix . UnF Not

add :: Term -> Term -> Term
add x y = Fix (BinF Add x y)

subterms :: Term -> [Term]
subterms t@(Fix l) = t : concatMap subterms l

genTerm :: Gen Term
genTerm = go (3 :: Int)
  where
    go 0 = leaf
    go d = frequency [(2, leaf), (3, f <$> go (d - 1)), (1, h <$> go (d - 1)), (1, add <$> go (d - 1) <*> go (d - 1))]
    leaf = elements [a, b, c, Fix (LitF (VBV 8 0))]

data Op = AddTerm Term | Merge Int Int | Rebuild
  deriving (Show)

genOps :: Gen [Op]
genOps = sized $ \size -> do
  n <- chooseInt (0, min 40 size)
  let ix = chooseInt (0, 12)
  replicateM n (frequency [(3, AddTerm <$> genTerm), (2, Merge <$> ix <*> ix), (1, pure Rebuild)])

shrinkOps :: [Op] -> [[Op]]
shrinkOps = shrinkList shrinkOp
  where
    shrinkOp (AddTerm (Fix l)) = AddTerm <$> toList l
    shrinkOp (Merge i j) = [Merge i' j | i' <- shrink i] ++ [Merge i j' | j' <- shrink j]
    shrinkOp Rebuild = []

pick :: [x] -> Int -> x
pick xs n = xs !! (n `mod` length xs)

runProgram :: [Op] -> ([[Text]], [[Bool]])
runProgram ops = runST $ do
  g <- newEGraph
  (ids, checks) <- foldM (step g) ([], []) ops
  rebuild g
  final <- checkInvariants g
  m <- forM ids (forM ids . equiv g)
  pure (checks ++ [final], m)
  where
    step g (ids, cs) (AddTerm t) = (\i -> (ids ++ [i], cs)) <$> addTerm g t
    step g (ids, cs) (Merge i j) = (ids, cs) <$ unless (null ids) (merge g (pick ids i) (pick ids j))
    step g (ids, cs) Rebuild = do rebuild g; vs <- checkInvariants g; pure (ids, cs ++ [vs])

type Blocks = [[Term]]

sameBlock :: Blocks -> Term -> Term -> Bool
sameBlock bs s t = any (\blk -> s `elem` blk && t `elem` blk) bs

union1 :: Blocks -> (Term, Term) -> Blocks
union1 bs (s, t) = let (hit, rest) = partition (\blk -> s `elem` blk || t `elem` blk) bs in concat hit : rest

merged :: [Op] -> Blocks
merged ops = foldl union1 (map pure (nub (concatMap subterms added))) pairs
  where
    added = [t | AddTerm t <- ops]
    soFar = scanl (\ts op -> case op of AddTerm t -> ts ++ [t]; _ -> ts) [] ops
    pairs = [(pick ts i, pick ts j) | (Merge i j, ts) <- zip ops soFar, not (null ts)]

close :: Blocks -> Blocks
close bs = case [(s, t) | s <- ts, t <- ts, not (sameBlock bs s t), congruent s t] of
  [] -> bs
  p : _ -> close (union1 bs p)
  where
    ts = concat bs
    congruent (Fix l1) (Fix l2) = void l1 == void l2 && and (zipWith (sameBlock bs) (toList l1) (toList l2))

agrees :: [Op] -> Property
agrees ops =
  let added = [t | AddTerm t <- ops]
      before = merged ops
      after = close before
      (_, m) = runProgram ops
      expected = [[sameBlock after s t | t <- added] | s <- added]
   in cover 10 (length after < length before) "congruence merged a pair the program did not name" $
        counterexample ("model classes " <> show after) (m === expected)

withGraph :: (forall s. EGraph s -> ST s x) -> x
withGraph k = runST (newEGraph >>= k)

abfafb :: EGraph s -> ST s (ClassId, ClassId, ClassId, ClassId)
abfafb g = (,,,) <$> addTerm g a <*> addTerm g b <*> addTerm g (f a) <*> addTerm g (f b)
