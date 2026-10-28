{-# LANGUAGE OverloadedStrings #-}

module Lozenge.SolverSpec (tests) where

import Control.Exception (bracket)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Lozenge.Solver
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Process (getCurrentPid, readProcess)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Z3 (requireZ3)

tests :: TestTree
tests =
  testGroup
    "Solver"
    [ testGroup
        "parseOutput"
        [ testCase "unsat, then the get-value error" $
            parseOutput "unsat\n(error \"line 6 column 16: model is not available\")\n" @?= Unsat,
          testCase "sat with a model in hex, binary and Bool" $
            parseOutput "sat\n((v_x #x7d)\n (v_y #b00101)\n (v_p true)\n (v_q false))\n"
              @?= Sat (Map.fromList [("v_x", 125), ("v_y", 5), ("v_p", 1), ("v_q", 0)]),
          testCase "sat without get-value" $ parseOutput "sat\n" @?= Sat Map.empty,
          testCase "unknown" $ parseOutput "unknown\n" @?= Unknown "z3 answered unknown",
          testCase "an error before the answer" $
            isError (parseOutput "(error \"line 2 column 31: invalid declaration\")\nsat\n"),
          testCase "a model it cannot read" $ isError (parseOutput "sat\n((v_x #xzz))\n"),
          testCase "a get-value error after sat" $ isError (parseOutput "sat\n(error \"unknown constant v_z\")\n"),
          testCase "no output" $ isError (parseOutput "")
        ],
      testCase "a missing z3 is a SolverError, not an exception" $
        withPath "/nonexistent" (runZ3 1000 "(check-sat)\n") >>= isError,
      requireZ3 "sat: the model is a counterexample" $ do
        r <- runZ3 5000 =<< golden "sub-comm"
        case r of
          Sat m
            | Just x <- Map.lookup "v_x" m,
              Just y <- Map.lookup "v_y" m -> do
                assertBool "x - y = y - x at width 8" ((x - y) `mod` 256 /= (y - x) `mod` 256)
                pure (show m)
          other -> assertFailure ("expected Sat with v_x and v_y, got " <> show other),
      requireZ3 "unsat" $ do
        r <- runZ3 5000 =<< golden "add-zero"
        r @?= Unsat
        pure "",
      requireZ3 "an error in the script" $ do
        runZ3 5000 "(assert x)\n(check-sat)\n" >>= isError
        pure "",
      requireZ3 "a timeout kills z3 and leaves no child process" $ do
        r <- runZ3 100 hardQuery
        r @?= Unknown "timeout after 100 ms"
        kids <- childProcesses
        kids @?= []
        pure ""
    ]

isError :: SolverResult -> IO ()
isError (SolverError _) = pure ()
isError other = assertFailure ("expected SolverError, got " <> show other)

golden :: String -> IO Text
golden name = TIO.readFile ("test/golden/smt/" <> name <> ".smt2")

-- Factor a product of two 32-bit primes: z3 needs far more than 100 ms.
hardQuery :: Text
hardQuery =
  T.unlines
    [ "(set-logic QF_BV)",
      "(declare-const x (_ BitVec 64))",
      "(declare-const y (_ BitVec 64))",
      "(assert (bvugt x #x0000000000000001))",
      "(assert (bvugt y #x0000000000000001))",
      "(assert (= (bvmul ((_ zero_extend 64) x) ((_ zero_extend 64) y)) #x0000000000000000ffffffea00000055))",
      "(check-sat)"
    ]

childProcesses :: IO [String]
childProcesses = do
  me <- show <$> getCurrentPid
  out <- readProcess "ps" ["-A", "-o", "ppid=,pid=,stat=,comm="] ""
  pure [l | l <- lines out, ppid : _ : _ : comm <- [words l], ppid == me, comm /= ["ps"]]

withPath :: String -> IO a -> IO a
withPath p act = bracket (lookupEnv "PATH") (maybe (unsetEnv "PATH") (setEnv "PATH")) (const (setEnv "PATH" p >> act))
