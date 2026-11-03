{-# LANGUAGE OverloadedStrings #-}

module Lozenge.FusionSpec (tests) where

import Data.Either (isLeft, isRight)
import Lozenge.EmitC (emitC)
import Lozenge.Fusion
import Lozenge.Graph (Graph, NodeId, Op (..), emptyGraph, insert, lower)
import TensorPrograms (Prog (..), programs)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Fusion"
    [ testGroup
        "fuse"
        [ testCase "a chain of adds and muls is one kernel" $
            fuse (build [inA, inB, Mul 0 1, Add 0 2]) 3
              @?= Right (Program [("a", 6), ("b", 6)] [Elementwise 6 (EwAdd (ld (InBuf 0)) (EwMul (ld (InBuf 0)) (ld (InBuf 1))))] (TmpBuf 0)),
          testCase "relu joins a chain" $
            fuse (build [inA, inB, Add 0 1, Relu 2, Mul 3 0]) 4
              @?= Right (Program [("a", 6), ("b", 6)] [Elementwise 6 (EwMul (EwRelu (EwAdd (ld (InBuf 0)) (ld (InBuf 1)))) (ld (InBuf 0)))] (TmpBuf 0)),
          testCase "a node used twice is materialised" $
            fuse (build [inA, inB, Add 0 1, Mul 2 2]) 3
              @?= Right
                ( Program
                    [("a", 6), ("b", 6)]
                    [Elementwise 6 (EwAdd (ld (InBuf 0)) (ld (InBuf 1))), Elementwise 6 (EwMul (ld (TmpBuf 0)) (ld (TmpBuf 0)))]
                    (TmpBuf 1)
                ),
          testCase "an add feeding a matmul is materialised" $
            fuse (build [inA, inB, inC, Add 0 1, MatMul 3 2]) 4
              @?= Right
                ( Program
                    [("a", 6), ("b", 6), ("c", 6)]
                    [Elementwise 6 (EwAdd (ld (InBuf 0)) (ld (InBuf 1))), MatMulK (TmpBuf 0) (InBuf 2) 2 3 2]
                    (TmpBuf 1)
                ),
          testCase "reshape is an alias: no kernel" $
            fuse (build [inA, Reshape [6] 0]) 1 @?= Right (Program [("a", 6)] [] (InBuf 0)),
          testCase "reshape breaks a chain" $
            fuse (build [inA, Add 0 0, Reshape [3, 2] 1, Mul 2 2]) 3
              @?= Right
                ( Program
                    [("a", 6)]
                    [Elementwise 6 (EwAdd (ld (InBuf 0)) (ld (InBuf 0))), Elementwise 6 (EwMul (ld (TmpBuf 0)) (ld (TmpBuf 0)))]
                    (TmpBuf 1)
                ),
          testCase "unreachable nodes are ignored" $
            fuse (build [inA, inB, Add 0 1]) 0 @?= Right (Program [("a", 6)] [] (InBuf 0)),
          testCase "concat, slice and transpose fields" $
            fuse (build [inA, Input "d" [2, 4], Concat 1 0 1, Slice 1 2 3 2, Transpose 3]) 4
              @?= Right
                ( Program
                    [("a", 6), ("d", 8)]
                    [ConcatK (InBuf 0) (InBuf 1) 2 3 4, SliceK (TmpBuf 0) 2 7 2 3, TransposeK (TmpBuf 1) 2 3]
                    (TmpBuf 2)
                ),
          testCase "concat along axis 0 is one block" $
            fuse (build [inA, inB, Concat 0 0 1]) 2 @?= Right (Program [("a", 6), ("b", 6)] [ConcatK (InBuf 0) (InBuf 1) 1 6 6] (TmpBuf 0)),
          testCase "an ill-shaped graph" $ assertBool "expected Left" (isLeft (fuse (build [inA, inC, Add 0 1]) 2)),
          testCase "a root that isn't there" $ assertBool "expected Left" (isLeft (fuse (build [inA]) 5))
        ],
      testGroup
        "emitC accepts every fused program"
        [ testCase name $ assertBool "fuse or emitC returned Left" (isRight (uncurry fuse (lower t) >>= emitC))
        | Prog name t <- programs
        ],
      testGroup
        "programCost"
        [ testCase "no kernels" $ programCost (Program [("a", 6)] [] (InBuf 0)) @?= Cost 0 0,
          testCase "elementwise counts distinct loads" $
            programCost (Program [("a", 6), ("b", 6)] [Elementwise 6 (EwAdd (ld (InBuf 0)) (EwMul (ld (InBuf 0)) (ld (InBuf 1))))] (TmpBuf 0))
              @?= Cost 1 18,
          testCase "add then matmul" $
            programCost
              (Program [("a", 6), ("b", 6), ("c", 6)] [Elementwise 6 (EwAdd (ld (InBuf 0)) (ld (InBuf 1))), MatMulK (TmpBuf 0) (InBuf 2) 2 3 2] (TmpBuf 1))
              @?= Cost 2 34,
          testCase "concat, slice, transpose" $
            programCost
              (Program [("a", 6), ("d", 8)] [ConcatK (InBuf 0) (InBuf 1) 2 3 4, SliceK (TmpBuf 0) 2 7 2 3, TransposeK (TmpBuf 1) 2 3] (TmpBuf 2))
              @?= Cost 3 52,
          testCase "totalCost" $ totalCost (Cost 2 34) @?= 2 * kernelWeight + 34
        ]
    ]

build :: [Op NodeId] -> Graph
build = foldl (\g n -> snd (insert n g)) emptyGraph

ld :: Buf -> Ew
ld = Load

inA, inB, inC :: Op NodeId
inA = Input "a" [2, 3]
inB = Input "b" [2, 3]
inC = Input "c" [3, 2]
