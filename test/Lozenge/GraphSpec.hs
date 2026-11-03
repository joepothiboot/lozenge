{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.GraphSpec (tests) where

import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import GHC.TypeLits (natSing)
import Lozenge.Graph
import Lozenge.Tensor (Tensor, shapeVal)
import Lozenge.Tensor qualified as T
import TensorPrograms (Prog (..), programs)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Graph"
    [ testGroup
        "insert and graphNodes"
        [ testCase "empty" $ graphNodes emptyGraph @?= [],
          testCase "ids count up from 0" $
            graphNodes (build [inA, inB, Add 0 1]) @?= [(0, inA), (1, inB), (2, Add 0 1)],
          testCase "an equal node is found, not added" $
            let (i, g) = insert (Add 0 1) (build [inA, inB, Add 0 1])
             in (i, length (graphNodes g)) @?= (2, 3),
          testCase "an input is found again" $ fst (insert inA (build [inA, inB])) @?= 0,
          testCase "Add 0 1 and Add 1 0 are two nodes" $ fst (insert (Add 1 0) (build [inA, inB, Add 0 1])) @?= 3,
          testCase "same name, another shape: a new node" $ fst (insert (Input "a" [6]) (build [inA])) @?= 1
        ],
      testGroup
        "shapeStep"
        [ Input "a" [2, 3] ==> [2, 3],
          Input "s" [] ==> [],
          Add [2, 3] [2, 3] ==> [2, 3],
          Mul [4] [4] ==> [4],
          MatMul [2, 3] [3, 4] ==> [2, 4],
          Transpose [2, 3] ==> [3, 2],
          Reshape [6] [2, 3] ==> [6],
          Reshape [] [1, 1] ==> [],
          Concat 0 [2, 3] [4, 3] ==> [6, 3],
          Concat 1 [2, 3] [2, 4] ==> [2, 7],
          Slice 1 1 2 [4, 3] ==> [4, 2],
          Slice 0 0 0 [2] ==> [0],
          Slice 1 3 0 [2, 3] ==> [2, 0],
          bad (Input "a" [2, -3]),
          bad (Add [2, 3] [3, 2]),
          bad (Mul [2] [2, 1]),
          bad (MatMul [2, 3] [4, 5]),
          bad (MatMul [2, 3, 1] [3, 4]),
          bad (Transpose [2, 3, 4]),
          bad (Reshape [4] [2, 3]),
          bad (Reshape [-2, -3] [6]),
          bad (Concat 2 [2, 3] [2, 3]),
          bad (Concat (-1) [2, 3] [2, 3]),
          bad (Concat 0 [2, 3] [2, 4]),
          bad (Concat 0 [2] [2, 3]),
          bad (Slice 1 2 2 [2, 3]),
          bad (Slice 1 0 1 [5]),
          bad (Slice 0 (-1) 1 [3]),
          bad (Slice 0 0 (-1) [3])
        ],
      testGroup
        "inferShapes"
        [ testCase "every node" $
            inferShapes (build [inA, inB, Add 0 1]) @?= Right (IM.fromList [(0, [2, 3]), (1, [2, 3]), (2, [2, 3])]),
          testCase "an ill-shaped node" $ assertLeft (inferShapes (build [inA, Input "c" [3, 2], Add 0 1])),
          testCase "a child that isn't there" $ assertLeft (inferShapes (build [inA, Add 0 7]))
        ],
      testGroup
        "lower"
        [ testCase "a" $ lowered a @?= ([(0, inA)], 0),
          testCase "a + a shares the input" $ lowered (T.Add a a) @?= ([(0, inA), (1, Add 0 0)], 1),
          testCase "a + b" $ lowered (T.Add a b) @?= ([(0, inA), (1, inB), (2, Add 0 1)], 2),
          testCase "children first, left to right" $
            lowered (T.MatMul (T.Add a b) c) @?= ([(0, inA), (1, inB), (2, Add 0 1), (3, inC), (4, MatMul 2 3)], 4),
          testCase "a common subexpression is one node" $
            lowered (T.Mul (T.Add a b) (T.Add a b)) @?= ([(0, inA), (1, inB), (2, Add 0 1), (3, Mul 2 2)], 3),
          testCase "reshape keeps its target" $ lowered (T.Reshape @'[6] a) @?= ([(0, inA), (1, Reshape [6] 0)], 1),
          testCase "transpose" $ lowered (T.Transpose a) @?= ([(0, inA), (1, Transpose 0)], 1),
          testCase "concat keeps its axis" $
            lowered (T.Concat (natSing @1) a b :: Tensor '[2, 6]) @?= ([(0, inA), (1, inB), (2, Concat 1 0 1)], 2),
          testCase "slice keeps axis, start and length" $
            lowered (T.Slice (natSing @1) (natSing @1) (natSing @2) a :: Tensor '[2, 2]) @?= ([(0, inA), (1, Slice 1 1 2 0)], 1),
          testCase "one name at two shapes is two inputs" $
            lowered (T.Add (T.Reshape @'[2, 3] (T.Var "a" :: Tensor '[6])) a)
              @?= ([(0, Input "a" [6]), (1, Reshape [2, 3] 0), (2, inA), (3, Add 1 2)], 3)
        ],
      testGroup
        "lower: the root has the program's shape"
        [ testCase name $ (inferShapes g >>= maybe (Left "no root") Right . IM.lookup r) @?= Right (shapeVal t)
        | Prog name t <- programs,
          let (g, r) = lower t
        ]
    ]

build :: [Op NodeId] -> Graph
build = foldl (\g n -> snd (insert n g)) emptyGraph

lowered :: Tensor s -> ([(NodeId, Op NodeId)], NodeId)
lowered t = let (g, r) = lower t in (graphNodes g, r)

inA, inB, inC :: Op NodeId
inA = Input "a" [2, 3]
inB = Input "b" [2, 3]
inC = Input "c" [3, 2]

a, b :: Tensor '[2, 3]
a = T.Var "a"
b = T.Var "b"

c :: Tensor '[3, 2]
c = T.Var "c"

(==>) :: Op Shape -> Shape -> TestTree
n ==> s = testCase (show n) (shapeStep n @?= Right s)

infix 1 ==>

bad :: Op Shape -> TestTree
bad n = testCase (show n <> " is ill-shaped") (assertLeft (shapeStep n))

assertLeft :: (Show r) => Either e r -> Assertion
assertLeft e = assertBool ("expected Left, got " <> either (const "Left") show e) (isLeft e)
