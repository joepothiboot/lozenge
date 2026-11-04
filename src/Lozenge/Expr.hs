{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Expr (
  Value (..),
  UnOp (..),
  BinOp (..),
  CmpOp (..),
  Expr (..),
  Env,
  validValue,
  unOpName,
  binOpName,
  cmpOpName,
)
where

import Data.Map.Strict (Map)
import Data.Text (Text)

data Value
  = VBool Bool
  | VBV Int Integer
  deriving (Eq, Ord, Show)

data UnOp
  = Not
  | Neg
  deriving (Eq, Ord, Show, Enum, Bounded)

data BinOp
  = Add
  | Sub
  | Mul
  | And
  | Or
  | Xor
  | Shl
  | Lshr
  deriving (Eq, Ord, Show, Enum, Bounded)

data CmpOp
  = Eq
  | Ult
  | Slt
  deriving (Eq, Ord, Show, Enum, Bounded)

data Expr
  = Var Text
  | Lit Value
  | Un UnOp Expr
  | Bin BinOp Expr Expr
  | Cmp CmpOp Expr Expr
  | Ite Expr Expr Expr
  deriving (Eq, Show)

type Env = Map Text Value

validValue :: Value -> Bool
validValue (VBool _) = True
validValue (VBV w v) = 1 <= w && w <= 64 && 0 <= v && v < 2 ^ w

unOpName :: UnOp -> Text
unOpName Not = "not"
unOpName Neg = "neg"

binOpName :: BinOp -> Text
binOpName Add = "add"
binOpName Sub = "sub"
binOpName Mul = "mul"
binOpName And = "and"
binOpName Or = "or"
binOpName Xor = "xor"
binOpName Shl = "shl"
binOpName Lshr = "lshr"

cmpOpName :: CmpOp -> Text
cmpOpName Eq = "="
cmpOpName Ult = "ult"
cmpOpName Slt = "slt"
