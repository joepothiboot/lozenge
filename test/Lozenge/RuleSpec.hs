{-# LANGUAGE OverloadedStrings #-}

module Lozenge.RuleSpec (tests) where

import Data.Map.Strict qualified as Map
import Lozenge.Expr
import Lozenge.Rule
import Lozenge.Typed (Ty (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Rule"
    [ testGroup
        "instantiate"
        [ testCase "Fixed ignores the width" $
            map (`instantiate` fixed) [0, 4, 8, 65] @?= replicate 4 (Just fixed),
          testCase "Generic at its own width is unchanged" $
            instantiate 8 generic @?= Just generic,
          testCase "Generic at 4 rewrites variable widths and keeps the low bits of literals" $
            instantiate 4 generic @?= Just generic4,
          testCase "Generic at width 1" $
            fmap ruleLhs (instantiate 1 generic) @?= Just (Bin And (Var "x") (bv 1 1)),
          testCase "Generic outside 1..64 is Nothing" $
            map (`instantiate` generic) [-1, 0, 65] @?= replicate 3 Nothing
        ]
    ]

bv :: Int -> Integer -> Expr
bv w v = Lit (VBV w v)

fixed :: Rule
fixed = generic{ruleWidth = Fixed}

generic :: Rule
generic =
  Rule
    { ruleName = "generic",
      ruleWidth = Generic,
      ruleVars = Map.fromList [("p", TBool), ("x", TBV 8)],
      ruleLhs = Bin And (Var "x") (bv 8 255),
      ruleRhs = Ite (Var "p") (Var "x") (Bin Or (Var "x") (bv 8 128)),
      rulePre = Just (Cmp Ult (Var "x") (bv 8 128))
    }

generic4 :: Rule
generic4 =
  generic
    { ruleVars = Map.fromList [("p", TBool), ("x", TBV 4)],
      ruleLhs = Bin And (Var "x") (bv 4 15),
      ruleRhs = Ite (Var "p") (Var "x") (Bin Or (Var "x") (bv 4 0)),
      rulePre = Just (Cmp Ult (Var "x") (bv 4 0))
    }
