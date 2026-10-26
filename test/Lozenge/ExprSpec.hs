module Lozenge.ExprSpec (tests) where

import Lozenge.Expr
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Expr"
    [ testGroup
        "validValue"
        [ valid (VBool False) True,
          valid (VBV 1 0) True,
          valid (VBV 1 1) True,
          valid (VBV 8 255) True,
          valid (VBV 64 (2 ^ (64 :: Int) - 1)) True,
          valid (VBV 1 2) False,
          valid (VBV 8 256) False,
          valid (VBV 8 (-1)) False,
          valid (VBV 0 0) False,
          valid (VBV (-1) 0) False,
          valid (VBV 65 0) False
        ]
    ]
  where
    valid v expected = testCase (show v) (validValue v @?= expected)
