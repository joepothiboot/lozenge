{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Golden (goldenText)
import Lozenge.CorpusSpec qualified as CorpusSpec
import Lozenge.EdgeSpec qualified as EdgeSpec
import Lozenge.EvalSpec qualified as EvalSpec
import Lozenge.EvalTSpec qualified as EvalTSpec
import Lozenge.ExprFSpec qualified as ExprFSpec
import Lozenge.ExprSpec qualified as ExprSpec
import Lozenge.ParseSpec qualified as ParseSpec
import Lozenge.PrettySpec qualified as PrettySpec
import Lozenge.RuleParseSpec qualified as RuleParseSpec
import Lozenge.RuleSpec qualified as RuleSpec
import Lozenge.SmtSpec qualified as SmtSpec
import Lozenge.SolverSpec qualified as SolverSpec
import Lozenge.SymExecSpec qualified as SymExecSpec
import Lozenge.TypecheckSpec qualified as TypecheckSpec
import Lozenge.TypedSpec qualified as TypedSpec
import Lozenge.VerifyBruteSpec qualified as VerifyBruteSpec
import Lozenge.VerifySmtSpec qualified as VerifySmtSpec
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
        TypedSpec.tests,
        EvalTSpec.tests,
        TypecheckSpec.tests,
        RuleSpec.tests,
        VerifyBruteSpec.tests,
        RuleParseSpec.tests,
        CorpusSpec.tests,
        SmtSpec.tests,
        SolverSpec.tests,
        VerifySmtSpec.tests,
        SymExecSpec.tests,
        ExprFSpec.tests,
        testGroup
          "harness"
          [ testCase "hunit" (1 + 1 @?= (2 :: Int)),
            props $ testProperty "reverse . reverse == id" (\xs -> reverse (reverse xs) == (xs :: [Int])),
            goldenText "golden" "smoke.txt" (pure "lozenge golden smoke test\n"),
            requireZ3 "z3 version" (readProcess "z3" ["--version"] "")
          ]
      ]
