{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.TypedSpec (tests) where

import GHC.TypeLits (SNat, natSing)
import Lozenge.Expr (BinOp (..), CmpOp (..), Expr (..), UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.Typed
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Typed"
    [ testGroup
        "erase"
        [ x ==> Var "x",
          TVar SBool "p" ==> Var "p",
          TLit (VBool True) ==> Lit (U.VBool True),
          bv w1 1 ==> Lit (U.VBV 1 1),
          bv w64 18446744073709551615 ==> Lit (U.VBV 64 18446744073709551615),
          bv (natSing @13) 4096 ==> Lit (U.VBV 13 4096),
          TUn Neg x ==> Un Neg (Var "x"),
          TBin Add x (bv w8 1) ==> Bin Add (Var "x") (Lit (U.VBV 8 1)),
          TCmp Slt z (bv w64 0) ==> Cmp Slt (Var "z") (Lit (U.VBV 64 0)),
          TIte (TCmp Ult x y) x y ==> Ite (Cmp Ult (Var "x") (Var "y")) (Var "x") (Var "y")
        ]
    ]

(==>) :: TExpr t -> Expr -> TestTree
te ==> e = testCase (show te) (erase te @?= e)

infix 1 ==>

w1 :: SNat 1
w1 = natSing

w8 :: SNat 8
w8 = natSing

w64 :: SNat 64
w64 = natSing

bv :: SNat w -> Integer -> TExpr ('TBV w)
bv w v = TLit (VBV w v)

x, y :: TExpr ('TBV 8)
x = TVar (SBV w8) "x"
y = TVar (SBV w8) "y"

z :: TExpr ('TBV 64)
z = TVar (SBV w64) "z"
