{-# LANGUAGE OverloadedStrings #-}


module Lozenge.EdgeSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golden (goldenText)
import Lozenge.Eval (eval)
import Lozenge.Expr
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

data Case = Case String Expr Value

tests :: TestTree
tests =
  testGroup
    "Edge cases"
    [ testGroup "unit" [testCase n (eval Map.empty e @?= Right v) | Case n e v <- cases],
      goldenText "golden" "edge-cases.txt" (pure (T.unlines (map line cases)))
    ]
  where
    line (Case n e _) = T.pack (n <> " = " <> show (eval Map.empty e))

un :: UnOp -> Int -> Integer -> Value -> Case
un op w a = Case (unwords ['w' : show w, show op, show a]) (Un op (Lit (VBV w a)))

bin :: BinOp -> Int -> Integer -> Integer -> Value -> Case
bin op w a b = Case (unwords ['w' : show w, show op, show a, show b]) (Bin op (Lit (VBV w a)) (Lit (VBV w b)))

cmp :: CmpOp -> Int -> Integer -> Integer -> Value -> Case
cmp op w a b = Case (unwords ['w' : show w, show op, show a, show b]) (Cmp op (Lit (VBV w a)) (Lit (VBV w b)))

-- | 2^64 - 1 and 2^63, written out so the derivations can refer to them.
max64, min64 :: Integer
max64 = 18446744073709551615
min64 = 9223372036854775808

cases :: [Case]
cases =
  -- Unary; "minimum value" = most negative signed value = 2^(w-1).
  [ un Neg 1 1 (VBV 1 1), -- (2 - 1) mod 2 = 1; at w=1 the minimum is 1 (= -1), its own negation
    un Not 1 0 (VBV 1 1), -- 2 - 1 - 0 = 1
    un Neg 8 128 (VBV 8 128), -- (256 - 128) mod 256 = 128: -(-128) overflows back to -128
    un Neg 13 4096 (VBV 13 4096), -- 2^13 = 8192; (8192 - 4096) mod 8192 = 4096
    un Neg 64 min64 (VBV 64 min64), -- (2^64 - 2^63) mod 2^64 = 2^63
    un Neg 64 1 (VBV 64 max64), -- (2^64 - 1) mod 2^64 = 2^64 - 1
    un Neg 64 0 (VBV 64 0), -- (2^64 - 0) mod 2^64 = 0, not 2^64
    un Not 64 0 (VBV 64 max64), -- 2^64 - 1 - 0
    -- Width 1: m = 2. A shift amount w+1 = 2 cannot be written at width 1 (max 1).
    bin Add 1 1 1 (VBV 1 0), -- (1 + 1) mod 2 = 0
    bin Sub 1 0 1 (VBV 1 1), -- (0 - 1) mod 2 = 1 (non-negative mod)
    bin Mul 1 1 1 (VBV 1 1), -- 1 * 1 = 1
    bin Shl 1 1 0 (VBV 1 1), -- shift 0 < w: 1 * 2^0 = 1
    bin Shl 1 1 1 (VBV 1 0), -- shift 1 = w: 0
    bin Lshr 1 1 1 (VBV 1 0), -- shift 1 = w: 0
    -- Width 8 shifts around w = 8.
    bin Shl 8 255 7 (VBV 8 128), -- 255 * 128 = 32640; 32640 mod 256 = 128 (= 127*256 + 128)
    bin Shl 8 1 8 (VBV 8 0), -- shift = w: 0
    bin Shl 8 1 9 (VBV 8 0), -- shift = w+1: 0
    bin Lshr 8 255 7 (VBV 8 1), -- 255 div 128 = 1
    bin Lshr 8 255 8 (VBV 8 0), -- shift = w: 0
    bin Lshr 8 255 9 (VBV 8 0), -- shift = w+1: 0
    -- Width 64: m = 2^64.
    bin Add 64 max64 1 (VBV 64 0), -- (2^64 - 1 + 1) mod 2^64 = 0
    bin Sub 64 0 1 (VBV 64 max64), -- (0 - 1) mod 2^64 = 2^64 - 1
    bin Shl 64 1 63 (VBV 64 min64), -- 2^63 < 2^64, kept
    bin Shl 64 1 64 (VBV 64 0), -- shift = w: 0
    bin Shl 64 1 65 (VBV 64 0), -- shift = w+1: 0
    bin Shl 64 1 max64 (VBV 64 0), -- shift = 2^64 - 1 >= w: 0 (and must not compute 2^(2^64-1))
    bin Lshr 64 max64 63 (VBV 64 1), -- (2^64 - 1) div 2^63 = 1
    bin Lshr 64 max64 64 (VBV 64 0), -- shift = w: 0
    bin Lshr 64 max64 65 (VBV 64 0), -- shift = w+1: 0
    bin Lshr 64 max64 max64 (VBV 64 0), -- huge shift: 0
    -- Multiplication overflow.
    bin Mul 8 16 16 (VBV 8 0), -- 256 mod 256 = 0
    bin Mul 8 255 255 (VBV 8 1), -- 65025 = 254*256 + 1, i.e. (-1)*(-1) = 1
    bin Mul 8 128 2 (VBV 8 0), -- 256 mod 256 = 0
    bin Mul 16 300 300 (VBV 16 24464), -- 90000 - 65536 = 24464
    bin Mul 64 4294967296 4294967296 (VBV 64 0), -- 2^32 * 2^32 = 2^64, mod 2^64 = 0
    bin Mul 64 max64 max64 (VBV 64 1), -- (2^64-1)^2 = 2^128 - 2^65 + 1, and 2^128, 2^65 are multiples of 2^64
    bin Mul 64 min64 3 (VBV 64 min64), -- 3 * 2^63 = 2^64 + 2^63, mod 2^64 = 2^63
    -- Signed comparison across the sign boundary; signed_w(v) = v - 2^w when v >= 2^(w-1).
    cmp Slt 1 1 0 (VBool True), -- signed_1(1) = -1 < 0
    cmp Ult 1 1 0 (VBool False), -- 1 < 0 is false
    cmp Slt 8 127 128 (VBool False), -- 127 < -128 is false
    cmp Slt 8 128 127 (VBool True), -- -128 < 127
    cmp Ult 8 127 128 (VBool True), -- unsigned 127 < 128: ult and slt disagree here
    cmp Slt 8 255 0 (VBool True), -- -1 < 0
    cmp Slt 8 0 255 (VBool False), -- 0 < -1 is false
    cmp Slt 8 128 255 (VBool True), -- -128 < -1
    cmp Slt 64 (min64 - 1) min64 (VBool False), -- 2^63 - 1 < -2^63 is false
    cmp Slt 64 min64 (min64 - 1) (VBool True), -- -2^63 < 2^63 - 1
    cmp Ult 64 (min64 - 1) min64 (VBool True), -- unsigned 2^63 - 1 < 2^63
    cmp Slt 64 max64 0 (VBool True) -- -1 < 0
  ]
