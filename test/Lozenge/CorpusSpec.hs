{-# LANGUAGE OverloadedStrings #-}

module Lozenge.CorpusSpec (tests, loadCorpus) where

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
        rules <- loadCorpus
        length rules @?= 30,
      goldenText "verdicts at widths 1-6" "corpus-verdicts.txt" $ do
        rules <- loadCorpus
        pure (T.unlines [ruleName r <> " @" <> T.pack (show w) <> ": " <> renderVerdict (verifyBrute w r) | r <- rules, w <- [1 .. 6]])
    ]

loadCorpus :: IO [Rule]
loadCorpus = do
  src <- TIO.readFile corpus
  either (fail . errorBundlePretty) pure (parseRules corpus src)
