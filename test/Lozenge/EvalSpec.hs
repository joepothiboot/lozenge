-- Text literals for variable names.
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.EvalSpec (tests) where

import Data.Either (isRight)
import Data.Map.Strict qualified as Map
import ExprGen (genExpr, shrinkExpr, testEnv)
import Lozenge.Eval
import Lozenge.Expr
import Props (props)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (counterexample, cover, forAllShrink, testProperty, within)

tests :: TestTree
tests =
  testGroup
    "Eval"
    [ testGroup "leaves" leaves,
      testGroup "arithmetic wraps" arith,
      testGroup "bitwise" bitwise,
      testGroup "shifts" shifts,
      testGroup "comparisons" comparisons,
      testGroup "ite" ites,
      testGroup "errors" errors,
      testGroup "error order" order,
      props $
        testGroup
          "properties"
          [ testProperty "eval never throws" $
              forAllShrink genExpr shrinkExpr $ \e ->
                within 1_000_000 (length (show (eval testEnv e)) >= 0),
            testProperty "eval results are valid values" $
              forAllShrink genExpr shrinkExpr $ \e ->
                let r = eval testEnv e
                 in counterexample (show r)
                      $ cover 40 (isRight r) "evaluates"
                      $ either (const True) validValue r
          ]
    ]

-- Helpers -------------------------------------------------------------------

bv :: Int -> Integer -> Expr
bv w v = Lit (VBV w v)

tt, ff :: Expr
tt = Lit (VBool True)
ff = Lit (VBool False)

env :: Env
env = testEnv

(==>) :: Expr -> Value -> TestTree
e ==> v = testCase (show e) (eval env e @?= Right v)

(!!>) :: Expr -> EvalError -> TestTree
e !!> err = testCase (show e) (eval env e @?= Left err)

infix 1 ==>, !!>

-- Cases ---------------------------------------------------------------------

leaves :: [TestTree]
leaves =
  [ bv 8 3 ==> VBV 8 3,
    tt ==> VBool True,
    Var "x" ==> VBV 8 200,
    Var "p" ==> VBool True
  ]

arith :: [TestTree]
arith =
  [ Bin Add (bv 8 200) (bv 8 100) ==> VBV 8 44,
    Bin Add (Var "x") (Var "x") ==> VBV 8 144,
    Bin Add (bv 1 1) (bv 1 1) ==> VBV 1 0,
    Bin Add (Var "z") (bv 64 1) ==> VBV 64 0,
    Bin Sub (bv 8 1) (bv 8 2) ==> VBV 8 255,
    Bin Sub (bv 64 0) (bv 64 1) ==> VBV 64 (2 ^ (64 :: Int) - 1),
    Bin Mul (bv 8 16) (bv 8 16) ==> VBV 8 0,
    Bin Mul (bv 8 15) (bv 8 17) ==> VBV 8 255,
    Bin Mul (bv 64 (2 ^ (63 :: Int))) (bv 64 2) ==> VBV 64 0,
    Bin Mul (Var "z") (Var "z") ==> VBV 64 1,
    Un Neg (bv 8 1) ==> VBV 8 255,
    Un Neg (bv 8 0) ==> VBV 8 0,
    Un Neg (bv 8 128) ==> VBV 8 128,
    Un Neg (bv 1 1) ==> VBV 1 1
  ]

bitwise :: [TestTree]
bitwise =
  [ Bin And (bv 8 0xF0) (bv 8 0x3C) ==> VBV 8 0x30,
    Bin Or (bv 8 0xF0) (bv 8 0x3C) ==> VBV 8 0xFC,
    Bin Xor (bv 8 0xF0) (bv 8 0x3C) ==> VBV 8 0xCC,
    Un Not (bv 8 0) ==> VBV 8 255,
    Un Not (bv 8 0x0F) ==> VBV 8 0xF0,
    Un Not (bv 1 1) ==> VBV 1 0,
    Un Not (Var "z") ==> VBV 64 0
  ]

shifts :: [TestTree]
shifts =
  [ Bin Shl (bv 8 1) (bv 8 3) ==> VBV 8 8,
    Bin Shl (bv 8 0x81) (bv 8 1) ==> VBV 8 2,
    Bin Shl (bv 8 1) (bv 8 7) ==> VBV 8 128,
    Bin Shl (bv 8 1) (bv 8 8) ==> VBV 8 0,
    Bin Shl (bv 8 255) (bv 8 255) ==> VBV 8 0,
    Bin Shl (bv 1 1) (bv 1 1) ==> VBV 1 0,
    Bin Shl (bv 64 1) (bv 64 63) ==> VBV 64 (2 ^ (63 :: Int)),
    Bin Shl (bv 64 1) (bv 64 64) ==> VBV 64 0,
    Bin Shl (Var "z") (Var "z") ==> VBV 64 0,
    Bin Lshr (bv 8 128) (bv 8 7) ==> VBV 8 1,
    Bin Lshr (bv 8 0x81) (bv 8 1) ==> VBV 8 0x40,
    Bin Lshr (bv 8 255) (bv 8 8) ==> VBV 8 0,
    Bin Lshr (bv 8 255) (bv 8 200) ==> VBV 8 0,
    Bin Lshr (Var "z") (bv 64 63) ==> VBV 64 1,
    Bin Lshr (Var "z") (Var "z") ==> VBV 64 0
  ]

comparisons :: [TestTree]
comparisons =
  [ Cmp Eq (Var "x") (bv 8 200) ==> VBool True,
    Cmp Eq (Var "x") (Var "y") ==> VBool False,
    Cmp Ult (bv 8 1) (bv 8 255) ==> VBool True,
    Cmp Ult (bv 8 255) (bv 8 1) ==> VBool False,
    Cmp Ult (bv 8 3) (bv 8 3) ==> VBool False,
    -- signed: 255 is -1 and 128 is -128 at width 8
    Cmp Slt (bv 8 255) (bv 8 1) ==> VBool True,
    Cmp Slt (bv 8 1) (bv 8 255) ==> VBool False,
    Cmp Slt (bv 8 127) (bv 8 128) ==> VBool False,
    Cmp Slt (bv 8 128) (bv 8 127) ==> VBool True,
    Cmp Slt (bv 8 3) (bv 8 3) ==> VBool False,
    -- width 1: 1 is -1
    Cmp Slt (bv 1 1) (bv 1 0) ==> VBool True,
    Cmp Slt (Var "z") (bv 64 0) ==> VBool True
  ]

ites :: [TestTree]
ites =
  [ Ite tt (bv 8 1) (bv 8 2) ==> VBV 8 1,
    Ite ff (bv 8 1) (bv 8 2) ==> VBV 8 2,
    Ite (Cmp Ult (Var "x") (Var "y")) (Var "x") (Var "y") ==> VBV 8 7
  ]

errors :: [TestTree]
errors =
  [ Var "nope" !!> UnboundVar "nope",
    Bin Add (Var "x") (Var "nope") !!> UnboundVar "nope",
    -- sort mismatches
    Bin Add (Var "p") (Var "x") !!> ExpectedBV,
    Bin Add (Var "x") tt !!> ExpectedBV,
    Un Not tt !!> ExpectedBV,
    Un Neg (Var "p") !!> ExpectedBV,
    Cmp Eq tt tt !!> ExpectedBV,
    Cmp Ult (Var "x") ff !!> ExpectedBV,
    Ite (Var "x") (Var "x") (Var "y") !!> ExpectedBool 8,
    Ite (bv 1 1) (bv 8 0) (bv 8 1) !!> ExpectedBool 1,
    Ite tt tt ff !!> ExpectedBV,
    Ite tt (Var "x") ff !!> ExpectedBV,
    -- width mismatches: (left, right) or (then, else)
    Bin Add (Var "x") (bv 16 1) !!> WidthMismatch 8 16,
    Bin Xor (bv 16 1) (Var "x") !!> WidthMismatch 16 8,
    Bin Shl (bv 8 1) (bv 64 1) !!> WidthMismatch 8 64,
    Cmp Slt (Var "x") (Var "z") !!> WidthMismatch 8 64,
    Ite tt (Var "x") (bv 16 0) !!> WidthMismatch 8 16,
    -- ill-formed values, as literals or in the environment
    bv 8 256 !!> InvalidValue (VBV 8 256),
    bv 8 (-1) !!> InvalidValue (VBV 8 (-1)),
    bv 0 0 !!> InvalidValue (VBV 0 0),
    bv 65 0 !!> InvalidValue (VBV 65 0),
    Bin Add (Var "x") (bv 8 300) !!> InvalidValue (VBV 8 300),
    testCase "ill-formed value in env" $
      eval (Map.insert "x" (VBV 8 300) env) (Var "x") @?= Left (InvalidValue (VBV 8 300))
  ]

order :: [TestTree]
order =
  [ Bin Add (Var "nope") tt !!> UnboundVar "nope",
    Bin Add tt (Var "nope") !!> UnboundVar "nope",
    Bin Add (Var "a") (Var "b2") !!> UnboundVar "a",
    Bin Add (Bin Add tt (Var "x")) (bv 16 0) !!> ExpectedBV,
    Bin Add (bv 16 0) (Bin Add tt (Var "x")) !!> ExpectedBV,
    Cmp Eq (bv 8 0) (bv 16 0) !!> WidthMismatch 8 16,
    Ite tt (Var "x") (Var "nope") !!> UnboundVar "nope",
    Ite ff (Var "nope") (Var "x") !!> UnboundVar "nope",
    Ite tt (Var "x") (Bin Add tt tt) !!> ExpectedBV,
    Ite (Var "x") (Var "nope") (Var "y") !!> UnboundVar "nope",
    Ite (Var "x") (bv 8 0) (bv 16 0) !!> ExpectedBool 8
  ]
