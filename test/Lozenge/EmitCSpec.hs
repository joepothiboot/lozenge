{-# LANGUAGE OverloadedStrings #-}

module Lozenge.EmitCSpec (tests) where

import CHarness (compileC, runExe, runProgram)
import Data.Either (isLeft)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Golden (goldenText)
import Lozenge.EmitC (emitC)
import Lozenge.Fusion
import Lozenge.Graph (Graph, NodeId, lower)
import Lozenge.TensorEval (InputError, evalTensor)
import Lozenge.TensorOpt (optimise)
import System.Directory (removeFile)
import TensorPrograms (Prog (..), genInputs, programs)
import Test.QuickCheck (forAll, ioProperty, (===))
import Test.Tasty (TestTree, localOption, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (QuickCheckTests (..), testProperty)
import Z3 (requireExe)

tests :: Bool -> TestTree
tests cc =
  testGroup
    "EmitC"
    [ goldenText "every kernel kind" "emitc-all-kernels.c" (either (fail . T.unpack) pure (emitC allKinds)),
      testGroup
        "malformed programs are refused"
        [ refused "read before write" (Program [] [Elementwise 1 (Load (TmpBuf 0))] (TmpBuf 0)),
          refused "no such input" (Program [("a", 1)] [Elementwise 1 (Load (InBuf 3))] (TmpBuf 0)),
          refused "elementwise size" (Program [("a", 6)] [Elementwise 7 (Load (InBuf 0))] (TmpBuf 0)),
          refused "matmul size" (Program [("a", 6), ("c", 6)] [MatMulK (InBuf 0) (InBuf 1) 2 2 2] (TmpBuf 0)),
          refused "slice past its block" (Program [("a", 6)] [SliceK (InBuf 0) 2 3 2 2] (TmpBuf 0)),
          refused "negative sizes" (Program [("a", 6)] [TransposeK (InBuf 0) (-2) (-3)] (TmpBuf 0)),
          refused "no such output" (Program [("a", 6)] [] (TmpBuf 0))
        ],
      testCase "input names never reach the C source" $
        assertBool "the name appears" $
          either (const False) (not . T.isInfixOf "evil") (emitC (Program [("evil */ name", 1)] [] (InBuf 0))),
      if cc then runs else requireExe "cc" "compiled C" (pure "")
    ]
  where
    refused name p = testCase name $ assertBool "expected Left" (isLeft (emitC p))

runs :: TestTree
runs =
  testGroup
    "compiled with cc"
    [ testGroup
        "hand-built programs"
        [ run "fused elementwise" (Program [("a", 6), ("b", 6)] [Elementwise 6 (EwAdd (Load in0) (EwMul (Load in0) (Load in1)))] (TmpBuf 0)) [a, b] [11, 42, 93, 164, 255, 366],
          run "matmul" (Program [("a", 6), ("c", 6)] [MatMulK in0 in1 2 3 2] (TmpBuf 0)) [a, c] [4, 5, 10, 11],
          run "transpose" (Program [("a", 6)] [TransposeK in0 2 3] (TmpBuf 0)) [a] [1, 4, 2, 5, 3, 6],
          run "concat along axis 1" (Program [("a", 6), ("b", 6)] [ConcatK in0 in1 2 3 3] (TmpBuf 0)) [a, b] [1, 2, 3, 10, 20, 30, 4, 5, 6, 40, 50, 60],
          run "slice along axis 1" (Program [("a", 6)] [SliceK in0 2 3 1 2] (TmpBuf 0)) [a] [2, 3, 5, 6],
          run "an empty slice" (Program [("a", 6)] [SliceK in0 2 3 3 0] (TmpBuf 0)) [a] [],
          run "no kernels: the output is an input" (Program [("a", 6), ("b", 6)] [] in1) [a, b] b,
          run "every kernel kind, chained" allKinds [a, c] [30, 132, 20, 30],
          run "doubles round-trip exactly" (Program [("p", 1), ("q", 1)] [Elementwise 1 (EwAdd (Load in0) (Load in1))] (TmpBuf 0)) [[0.1], [0.2]] [0.1 + 0.2]
        ],
      localOption (QuickCheckTests 50) $
        testGroup
          "same result as evalTensor on random inputs"
          [ differential label pass p
          | (label, pass) <- [("unoptimised", (,)), ("optimised", optimise 8)],
            p <- programs
          ]
    ]
  where
    run name p ins expected = testCase name (runProgram p ins >>= (@?= expected))
    in0 = InBuf 0
    in1 = InBuf 1

differential :: String -> (Graph -> NodeId -> (Graph, NodeId)) -> Prog -> TestTree
differential label pass (Prog name t) =
  withResource compile (removeFile . fst) $ \getExe ->
    testProperty (name <> ", " <> label) $ forAll genInputs $ \env -> ioProperty $ do
      (exe, ins) <- getExe
      let doubles = fmap fromInteger <$> env
      out <- runExe exe [M.findWithDefault [] n doubles | (n, _) <- ins]
      pure (Right out === (evalTensor doubles t :: Either InputError [Double]))
  where
    compile = do
      p <- either (fail . T.unpack) pure (uncurry fuse (uncurry pass (lower t)))
      src <- either (fail . T.unpack) pure (emitC p)
      exe <- compileC src
      pure (exe, progInputs p)

allKinds :: Program
allKinds =
  Program
    [("a", 6), ("c", 6)]
    [ MatMulK (InBuf 0) (InBuf 1) 2 3 2,
      Elementwise 4 (EwAdd (Load (TmpBuf 0)) (EwMul (Load (TmpBuf 0)) (Load (TmpBuf 0)))),
      TransposeK (TmpBuf 1) 2 2,
      ConcatK (TmpBuf 2) (TmpBuf 1) 1 4 4,
      SliceK (TmpBuf 3) 1 8 2 4
    ]
    (TmpBuf 4)

a, b, c :: [Double]
a = [1 .. 6]
b = [10, 20 .. 60]
c = [1, 0, 0, 1, 1, 1]
