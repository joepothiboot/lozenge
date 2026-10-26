{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Lozenge.Typed (
  Ty (..),
  SingTy (..),
  Value (..),
  TExpr (..),
  SomeExpr (..),
  erase,
)
where

import Data.Text (Text)
import GHC.TypeLits (Nat, SNat)
import Lozenge.Expr (BinOp, CmpOp, Expr, UnOp)

data Ty
  = TBool
  | TBV Nat
  deriving (Eq, Show)

data SingTy (t :: Ty) where
  SBool :: SingTy 'TBool
  SBV :: SNat w -> SingTy ('TBV w)

deriving instance Eq (SingTy t)

deriving instance Show (SingTy t)

data Value (t :: Ty) where
  VBool :: Bool -> Value 'TBool
  VBV :: SNat w -> Integer -> Value ('TBV w)

deriving instance Eq (Value t)

deriving instance Show (Value t)

data TExpr (t :: Ty) where
  TVar :: SingTy t -> Text -> TExpr t
  TLit :: Value t -> TExpr t
  TUn :: UnOp -> TExpr ('TBV w) -> TExpr ('TBV w)
  TBin :: BinOp -> TExpr ('TBV w) -> TExpr ('TBV w) -> TExpr ('TBV w)
  TCmp :: CmpOp -> TExpr ('TBV w) -> TExpr ('TBV w) -> TExpr 'TBool
  TIte :: TExpr 'TBool -> TExpr ('TBV w) -> TExpr ('TBV w) -> TExpr ('TBV w)

deriving instance Show (TExpr t)

data SomeExpr where
  SomeExpr :: SingTy t -> TExpr t -> SomeExpr

deriving instance Show SomeExpr

erase :: TExpr t -> Expr
erase = error "TODO: erase"
