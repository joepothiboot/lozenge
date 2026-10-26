{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Golden (goldenText)
import Lozenge.EdgeSpec qualified as EdgeSpec
import Lozenge.EvalSpec qualified as EvalSpec
import Lozenge.ExprSpec qualified as ExprSpec
import Lozenge.ParseSpec qualified as ParseSpec
import Lozenge.PrettySpec qualified as PrettySpec
import Props (props)
import System.Process (readProcess)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import Z3 (requireZ3)

main :: IO ()
main =
  defaultMain $
    testGroup
      "lozenge"
      [ ExprSpec.tests,
        ParseSpec.tests,
        EvalSpec.tests,
        PrettySpec.tests,
        EdgeSpec.tests,
        testGroup
          "harness"
          [ testCase "hunit" (1 + 1 @?= (2 :: Int)),
            props $ testProperty "reverse . reverse == id" (\xs -> reverse (reverse xs) == (xs :: [Int])),
            goldenText "golden" "smoke.txt" (pure "lozenge golden smoke test\n"),
            requireZ3 "z3 version" (readProcess "z3" ["--version"] "")
          ]
      ]
