module Lozenge.Expr
  ( Value (..),
    UnOp (..),
    BinOp (..),
    CmpOp (..),
    Expr (..),
    Env,
    validValue,
  )
where

import Data.Map.Strict (Map)
import Data.Text (Text)

data Value
  = VBool Bool
  | VBV Int Integer
  deriving (Eq, Show)

data UnOp
  = Not
  | Neg
  deriving (Eq, Show, Enum, Bounded)

data BinOp
  = Add
  | Sub
  | Mul
  | And
  | Or
  | Xor
  | Shl
  | Lshr
  deriving (Eq, Show, Enum, Bounded)

data CmpOp
  = Eq
  | Ult
  | Slt
  deriving (Eq, Show, Enum, Bounded)

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
validValue = error "TODO: validValue"
