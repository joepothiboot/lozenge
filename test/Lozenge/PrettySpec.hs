{-# LANGUAGE OverloadedStrings #-}

module Lozenge.PrettySpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Lozenge.Expr
import Lozenge.Pretty (render)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Pretty"
    [ renders x "x",
      renders (Lit (VBool True)) "true",
      renders (Lit (VBool False)) "false",
      renders (Lit (VBV 8 3)) "(const 8 3)",
      renders (Lit (VBV 64 18446744073709551615)) "(const 64 18446744073709551615)",
      renders (Bin Add x (Lit (VBV 8 3))) "(add x (const 8 3))",
      renders (Ite (Cmp Ult x y) x y) "(ite (ult x y) x y)",
      renders (Un Not x) "(not x)",
      renders (Un Neg x) "(neg x)",
      renders (Bin Sub x y) "(sub x y)",
      renders (Bin Mul x y) "(mul x y)",
      renders (Bin And x y) "(and x y)",
      renders (Bin Or x y) "(or x y)",
      renders (Bin Xor x y) "(xor x y)",
      renders (Bin Shl x y) "(shl x y)",
      renders (Bin Lshr x y) "(lshr x y)",
      renders (Cmp Eq x y) "(= x y)",
      renders (Cmp Slt x y) "(slt x y)",
      renders (Un Neg (Un Not (Bin Add x (Un Neg y)))) "(neg (not (add x (neg y))))",
      testCase "fits in 80 columns => one line" $
        T.lines (render wide) @?= [render wide]
    ]
  where
    x = Var "x"
    y = Var "y"
    -- 72 characters when rendered on one line
    wide = Bin Add (Bin Mul (Var "alpha") (Var "beta")) (Ite (Cmp Slt (Var "gamma") (Lit (VBV 8 1))) (Var "delta") (Lit (VBV 8 255)))

renders :: Expr -> Text -> TestTree
renders e expected = testCase (T.unpack expected) (render e @?= expected)
