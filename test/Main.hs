{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Maybe (isJust)
import Golden (goldenText)
import Lozenge.CliSpec qualified as CliSpec
import Lozenge.CorpusSpec qualified as CorpusSpec
import Lozenge.CriticalSpec qualified as CriticalSpec
import Lozenge.EGraphSpec qualified as EGraphSpec
import Lozenge.EdgeSpec qualified as EdgeSpec
import Lozenge.EmitCSpec qualified as EmitCSpec
import Lozenge.EvalSpec qualified as EvalSpec
import Lozenge.EvalTSpec qualified as EvalTSpec
import Lozenge.ExprFSpec qualified as ExprFSpec
import Lozenge.ExprSpec qualified as ExprSpec
import Lozenge.FusionSpec qualified as FusionSpec
import Lozenge.GraphSpec qualified as GraphSpec
import Lozenge.ParseSpec qualified as ParseSpec
import Lozenge.PrettySpec qualified as PrettySpec
import Lozenge.RewriteSpec qualified as RewriteSpec
import Lozenge.RuleParseSpec qualified as RuleParseSpec
import Lozenge.RuleSpec qualified as RuleSpec
import Lozenge.SaturateSpec qualified as SaturateSpec
import Lozenge.SmtSpec qualified as SmtSpec
import Lozenge.SolverSpec qualified as SolverSpec
import Lozenge.SymExecSpec qualified as SymExecSpec
import Lozenge.TensorOptSpec qualified as TensorOptSpec
import Lozenge.TensorSpec qualified as TensorSpec
import Lozenge.TypecheckSpec qualified as TypecheckSpec
import Lozenge.TypedSpec qualified as TypedSpec
import Lozenge.UnionFindSpec qualified as UnionFindSpec
import Lozenge.VerifyBruteSpec qualified as VerifyBruteSpec
import Lozenge.VerifySmtSpec qualified as VerifySmtSpec
import Props (props)
import System.Directory (findExecutable)
import System.Process (readProcess)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import Z3 (requireZ3)

main :: IO ()
main = do
  z3 <- isJust <$> findExecutable "z3"
  cc <- isJust <$> findExecutable "cc"
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
        RewriteSpec.tests,
        CriticalSpec.tests,
        UnionFindSpec.tests,
        EGraphSpec.tests,
        SaturateSpec.tests,
        TensorSpec.tests,
        GraphSpec.tests,
        FusionSpec.tests,
        TensorOptSpec.tests,
        EmitCSpec.tests cc,
        CliSpec.tests z3,
        testGroup
          "harness"
          [ testCase "hunit" (1 + 1 @?= (2 :: Int)),
            props $ testProperty "reverse . reverse == id" (\xs -> reverse (reverse xs) == (xs :: [Int])),
            goldenText "golden" "smoke.txt" (pure "lozenge golden smoke test\n"),
            requireZ3 "z3 version" (readProcess "z3" ["--version"] "")
          ]
      ]
