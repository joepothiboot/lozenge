{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Lozenge.Typed (
  Ty (..),
  SingTy (..),
  Value (..),
  TExpr (..),
  SomeExpr (..),
  erase,
  widthOf,
)
where

import Data.Text (Text)
import GHC.TypeLits (Nat, SNat)
import GHC.TypeNats (fromSNat)
import Lozenge.Expr (BinOp, CmpOp, Expr (..), UnOp)
import Lozenge.Expr qualified as U

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
erase (TVar _ x) = Var x
erase (TLit (VBool b)) = Lit (U.VBool b)
erase (TLit (VBV w v)) = Lit (U.VBV (widthOf w) v)
erase (TUn op a) = Un op (erase a)
erase (TBin op a b) = Bin op (erase a) (erase b)
erase (TCmp op a b) = Cmp op (erase a) (erase b)
erase (TIte c t e) = Ite (erase c) (erase t) (erase e)

widthOf :: SNat w -> Int
widthOf = fromIntegral . fromSNat
