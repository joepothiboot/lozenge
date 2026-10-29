module Lozenge.UnionFindSpec (tests) where

import Control.Monad (forM, replicateM, replicateM_)
import Control.Monad.ST (ST, runST)
import Data.List (partition)
import Lozenge.UnionFind
import Props (props)
import Test.QuickCheck (Result (..), chatty, maxSuccess, quickCheckWithResult, stdArgs)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, Property, checkCoverage, chooseInt, conjoin, counterexample, cover, forAllShrinkShow, frequency, property, shrink, shrinkList, sized, testProperty, (.&&.), (===))

tests :: TestTree
tests =
  testGroup
    "UnionFind"
    [ testGroup
        "makeSet"
        [ testCase "an empty structure has no elements" $
            runST (newUF >>= parents) @?= [],
          testCase "numbers elements 0, 1, 2 and makes each its own parent" $
            runST (do uf <- newUF; xs <- replicateM 3 (makeSet uf); ps <- parents uf; pure (xs, ps)) @?= ([0, 1, 2], [0, 1, 2]),
          testCase "grows past any initial capacity" $
            runST (do uf <- newUF; xs <- replicateM 1000 (makeSet uf); ps <- parents uf; pure (xs, ps)) @?= ([0 .. 999], [0 .. 999])
        ],
      testGroup
        "parents"
        [ testCase "after two unions of pairs and a union of the pairs" $
            withSets 4 (\uf -> mapM_ (uncurry (union uf)) [(0, 1), (2, 3), (0, 2)] >> parents uf) @?= [0, 0, 0, 2]
        ],
      testGroup
        "find"
        [ testCase "a singleton is its own root" $
            withSets 3 (\uf -> traverse (find uf) [0, 1, 2]) @?= [0, 1, 2],
          testCase "compresses the whole path, and only it" $
            withSets
              5
              ( \uf -> do
                  mapM_ (uncurry (union uf)) [(0, 1), (2, 3), (0, 2)]
                  r <- find uf 3
                  ps <- parents uf
                  pure (r, ps)
              )
              @?= (0, [0, 0, 0, 0, 4]),
          props $
            testProperty "after find, every element on the old path has depth <= 1" $
              forAllShrinkShow genOps shrinkOps show (checkCoverage . compressLaw)
        ],
      testGroup
        "union"
        [ testCase "a tie: the first argument's root wins" $
            withSets 2 (\uf -> (,) <$> union uf 0 1 <*> parents uf) @?= (0, [0, 0]),
          testCase "a tie the other way round" $
            withSets 2 (\uf -> (,) <$> union uf 1 0 <*> parents uf) @?= (1, [1, 1]),
          testCase "the smaller rank goes under the larger, whatever the order" $
            withSets 3 (\uf -> union uf 0 1 >> (,) <$> union uf 2 0 <*> parents uf) @?= (0, [0, 0, 0]),
          testCase "already in one set: returns the root, changes nothing" $
            withSets 2 (\uf -> union uf 0 1 >> (,) <$> union uf 1 0 <*> parents uf) @?= (0, [0, 0]),
          props $
            testProperty "union by rank: 2 ^ depth <= the size of the element's set" $
              forAllShrinkShow genOps shrinkOps show (checkCoverage . rankLaw)
        ],
      testGroup
        "against a model"
        [ props $
            testProperty "find agrees with a list of sets after every step" $
              checkCoverage (agrees runUF),
          testCase "shrinking: a known bug fails in at most 5 steps" $ do
            r <- quickCheckWithResult stdArgs{chatty = False, maxSuccess = 1000} (agrees runBuggy)
            case r of
              Failure{failingTestCase = shown : _} ->
                assertBool ("shrunk to " <> shown) (length (read shown :: [Op]) <= 5)
              _ -> assertFailure ("the model test missed a known bug: " <> show r)
        ]
    ]

-- | A structure with @n@ singletons, @0@ to @n - 1@.
withSets :: Int -> (forall s. UF s -> ST s a) -> a
withSets n k = runST (do uf <- newUF; replicateM_ n (makeSet uf); k uf)

-- | One step of a test program. Elements are numbered as 'makeSet' numbers
data Op = MakeSet | Union Int Int | Find Int
  deriving (Eq, Show, Read)

-- | The number of elements before each step, and after the last.
counts :: [Op] -> [Int]
counts = scanl (\n op -> if op == MakeSet then n + 1 else n) 0

valid :: [Op] -> Bool
valid ops = and (zipWith ok ops (counts ops))
  where
    ok MakeSet _ = True
    ok (Union a b) n = el n a && el n b
    ok (Find a) n = el n a
    el n x = 0 <= x && x < n

-- | Valid programs of up to 60 steps, two unions to each 'makeSet'.
genOps :: Gen [Op]
genOps = sized (\size -> go (min 60 size) 0)
  where
    go :: Int -> Int -> Gen [Op]
    go 0 _ = pure []
    go k n = do
      let el = chooseInt (0, n - 1)
      op <-
        frequency $
          (2, pure MakeSet)
            : if n == 0 then [] else [(4, Union <$> el <*> el), (1, Find <$> el)]
      (op :) <$> go (k - 1) (if op == MakeSet then n + 1 else n)

-- | Drop an element, drop steps, or lower element numbers, keeping the
shrinkOps :: [Op] -> [[Op]]
shrinkOps ops = [dropElement k ops | k <- [0 .. last (counts ops) - 1]] ++ filter valid (shrinkList shrinkOp ops)
  where
    shrinkOp MakeSet = []
    shrinkOp (Union a b) = [Union a' b | a' <- shrink a] ++ [Union a b' | b' <- shrink b]
    shrinkOp (Find a) = Find <$> shrink a

-- | Remove element @k@: the 'MakeSet' that makes it and every step that
dropElement :: Int -> [Op] -> [Op]
dropElement k ops =
  [renumber op | (op, n) <- zip ops (counts ops), not (op == MakeSet && n == k), k `notElem` named op]
  where
    named (Union a b) = [a, b]
    named (Find a) = [a]
    named MakeSet = []
    renumber (Union a b) = Union (down a) (down b)
    renumber (Find a) = Find (down a)
    renumber MakeSet = MakeSet
    down x = if x > k then x - 1 else x

step :: UF s -> Op -> ST s Int
step uf MakeSet = makeSet uf
step uf (Union a b) = union uf a b
step uf (Find a) = find uf a

run :: [Op] -> (forall s. UF s -> ST s a) -> a
run ops k = runST (do uf <- newUF; mapM_ (step uf) ops; k uf)

-- | The path from @x@ to its root. Cut short if the parents have a cycle.
pathOf :: [Int] -> Int -> [Int]
pathOf ps x0 = take (length ps + 1) (go x0)
  where
    go x = let p = ps !! x in if p == x then [x] else x : go p

depth :: [Int] -> Int -> Int
depth ps x = length (pathOf ps x) - 1

root :: [Int] -> Int -> Int
root ps x = last (pathOf ps x)

-- | Run the program, then 'find' its deepest element.
compressLaw :: [Op] -> Property
compressLaw ops = case run ops findDeepest of
  Nothing -> property True
  Just (before, x, after) ->
    let path = pathOf before x
        els = [0 .. length before - 1]
     in cover 15 (length path > 2) "the path has 2 or more edges" $
          counterexample ("parents before " <> show before <> ", find " <> show x <> ", parents after " <> show after) $
            [y | y <- path, depth after y > 1]
              === []
              .&&. map (root after) els
              === map (root before) els
              .&&. [y | y <- els, y `notElem` path, after !! y /= before !! y]
              === []
  where
    findDeepest :: UF s -> ST s (Maybe ([Int], Int, [Int]))
    findDeepest uf = do
      before <- parents uf
      if null before
        then pure Nothing
        else do
          let x = snd (maximum [(depth before y, y) | y <- [0 .. length before - 1]])
          _ <- find uf x
          after <- parents uf
          pure (Just (before, x, after))

rankLaw :: [Op] -> Property
rankLaw ops =
  let ps = run ops parents
      els = [0 .. length ps - 1]
      size x = length [y | y <- els, root ps y == root ps x]
   in cover 15 (any (\x -> depth ps x >= 2) els) "some depth >= 2" $
        counterexample ("parents " <> show ps) $
          conjoin [counterexample ("element " <> show x) (2 ^ depth ps x <= size x) | x <- els]

-- | What a step returned, and the 'find' of every element after it.
type Step = (Int, [Int])

runUF :: [Op] -> [Step]
runUF ops = runST $ do
  uf <- newUF
  forM (zip ops (drop 1 (counts ops))) $ \(op, n) ->
    (,) <$> step uf op <*> traverse (find uf) [0 .. n - 1]

-- | The naive model: a list of disjoint sets.
type Model = [[Int]]

modelStep :: Model -> Op -> Model
modelStep m MakeSet = [length (concat m)] : m
modelStep m (Union a b) = let (hit, rest) = partition (\s -> a `elem` s || b `elem` s) m in concat hit : rest
modelStep m (Find _) = m

same :: Model -> Int -> Int -> Bool
same m a b = any (\s -> a `elem` s && b `elem` s) m

-- | After each step: two elements have equal 'find's iff the model has them
agrees :: ([Op] -> [Step]) -> Property
agrees runner = forAllShrinkShow genOps shrinkOps show $ \ops ->
  cover 40 (length (filter isUnion ops) >= 5) "5 or more unions" $
    conjoin (zipWith3 checkStep ops (drop 1 (scanl modelStep [] ops)) (runner ops))
  where
    isUnion (Union _ _) = True
    isUnion _ = False

checkStep :: Op -> Model -> Step -> Property
checkStep op m (r, reps) =
  counterexample ("after " <> show op <> ": model " <> show m <> ", finds " <> show reps) $
    [(a, b) | a <- els, b <- els, (reps !! a == reps !! b) /= same m a b]
      === []
      .&&. [a | a <- els, not (same m a (reps !! a))]
      === []
      .&&. r
      === expected
  where
    els = [0 .. length (concat m) - 1]
    expected = case op of
      MakeSet -> length els - 1
      Union a _ -> reps !! a
      Find a -> reps !! a

-- | A union-find with a classic bug, to check that the model test catches it
runBuggy :: [Op] -> [Step]
runBuggy = map snd . drop 1 . scanl go ([], (0, []))
  where
    go (ps, _) op =
      let ps' = case op of
            MakeSet -> ps ++ [length ps]
            Union a b -> [if i == a then root ps b else p | (i, p) <- zip [0 ..] ps]
            Find _ -> ps
          r = case op of
            MakeSet -> length ps
            Union a _ -> root ps' a
            Find a -> root ps' a
       in (ps', (r, map (root ps') [0 .. length ps' - 1]))
