{-# LANGUAGE OverloadedStrings #-}

module Lozenge.CorpusSpec (tests) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golden (goldenText)
import Lozenge.Rule (Rule (..))
import Lozenge.RuleParse (parseRules)
import Lozenge.VerifyBrute (renderVerdict, verifyBrute)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Text.Megaparsec (errorBundlePretty)

corpus :: FilePath
corpus = "rules/bitvector.rules"

tests :: TestTree
tests =
  testGroup
    "Corpus"
    [ testCase "rules/bitvector.rules has 30 rules" $ do
        rules <- load
        length rules @?= 30,
      goldenText "verdicts at widths 1-6" "corpus-verdicts.txt" $ do
        rules <- load
        pure (T.unlines [ruleName r <> " @" <> T.pack (show w) <> ": " <> renderVerdict (verifyBrute w r) | r <- rules, w <- [1 .. 6]])
    ]

load :: IO [Rule]
load = do
  src <- TIO.readFile corpus
  either (fail . errorBundlePretty) pure (parseRules corpus src)
