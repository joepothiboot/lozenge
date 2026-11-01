{-# LANGUAGE OverloadedStrings #-}

module Lozenge.CliSpec (tests) where

import Data.Aeson (ToJSON)
import Data.Aeson.Text (encodeToLazyText)
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Lazy (Text)
import Golden (goldenText)
import Lozenge.Cli (Command (..), Cost (..), Engine (..), Solver (..), run)
import Lozenge.Json qualified as J
import System.Exit (ExitCode (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Z3 (requireZ3)

corpus :: FilePath
corpus = "rules/bitvector.rules"

tests :: Bool -> TestTree
tests z3 =
  testGroup
    "Cli"
    [ testGroup
        "golden"
        [ golden "verify" "cli-verify.txt" False (Verify corpus 6 Brute),
          golden "verify --json" "cli-verify.json" True (Verify corpus 6 Brute),
          golden "optimize --engine egraph --cost shifts" "cli-optimize.txt" False (Optimize "examples/strength.ir" corpus 8 Shifts EGraph),
          golden "optimize --engine greedy --json" "cli-optimize.json" True (Optimize "examples/strength.ir" corpus 8 Size Greedy),
          withZ3 "critical-pairs" (golden "critical-pairs" "cli-critical-pairs.txt" False (CriticalPairs corpus 8)),
          withZ3 "critical-pairs --json" (golden "critical-pairs --json" "cli-critical-pairs.json" True (CriticalPairs corpus 8))
        ],
      testCase "verify exits 1 when a rule has a counterexample" $ do
        r <- run False (Verify corpus 6 Brute)
        fst <$> r @?= Right (ExitFailure 1),
      testCase "a missing file is an error, not an exception" $ do
        r <- run False (Verify "no-such.rules" 8 Brute)
        assertBool "expected Left" (isLeft r),
      testCase "JSON field names, tags, and omitted solvers" $ do
        json (J.VerifyReport 6 [J.RuleReport "r" (Just (J.Invalid (Map.fromList [("x", J.VBV 6 0), ("p", J.VBool True)]) (J.VBV 6 63) (J.VBV 6 1))) Nothing, J.RuleReport "s" Nothing (Just (J.Unsupported "why"))])
          @?= "{\"width\":6,\"rules\":[{\"name\":\"r\",\"brute\":{\"verdict\":\"invalid\",\"assignment\":{\"p\":true,\"x\":{\"width\":6,\"value\":0}},\"lhs\":{\"width\":6,\"value\":63},\"rhs\":{\"width\":6,\"value\":1}}},{\"name\":\"s\",\"smt\":{\"verdict\":\"unsupported\",\"reason\":\"why\"}}]}"
        json (J.Pair "a" "b" [0, 1] "p" "l" "r" (J.NotJoined "x" "y") (Just J.Valid))
          @?= "{\"outer\":\"a\",\"inner\":\"b\",\"position\":[0,1],\"peak\":\"p\",\"left\":\"l\",\"right\":\"r\",\"join\":{\"result\":\"not-joined\",\"left\":\"x\",\"right\":\"y\"},\"check\":{\"verdict\":\"valid\"}}"
        json [J.Joined "t", J.Unknown] @?= "[{\"result\":\"joined\",\"normalForm\":\"t\"},{\"result\":\"unknown\"}]"
        json (J.OptimizeReport 8 "i" "o" 5 3 "saturated" [J.Refused "r" "why"])
          @?= "{\"width\":8,\"input\":\"i\",\"output\":\"o\",\"inputCost\":5,\"outputCost\":3,\"stop\":\"saturated\",\"refused\":[{\"rule\":\"r\",\"reason\":\"why\"}]}"
    ]
  where
    golden name file asJson cmd = goldenText name file (run asJson cmd >>= either (fail . T.unpack) (pure . snd))
    withZ3 name t = if z3 then t else requireZ3 name (pure "")

json :: (ToJSON a) => a -> Text
json = encodeToLazyText
