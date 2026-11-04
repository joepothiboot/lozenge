{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Lozenge.Typecheck (
  Context,
  TypeError (..),
  typecheck,
  checkTy,
)
where

import Control.Monad (when)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Type.Equality (testEquality, (:~:) (Refl))
import GHC.TypeLits (SNat)
import GHC.TypeNats (withSomeSNat)
import Lozenge.Expr (Expr (..), validValue)
import Lozenge.Expr qualified as U
import Lozenge.Typed (SingTy (..), SomeExpr (..), TExpr (..), Ty (..), Value (..), widthOf)

type Context = Map Text Ty

data TypeError
  = UnboundVar Text
  | ExpectedBV
  | ExpectedBool Int
  | WidthMismatch Int Int
  | InvalidValue U.Value
  | InvalidSort Ty
  deriving (Eq, Show)

typecheck :: Context -> Expr -> Either TypeError SomeExpr
typecheck ctx = go
  where
    go (Var x) = do
      ty <- maybe (Left (UnboundVar x)) Right (Map.lookup x ctx)
      checkTy ty
      pure $ case ty of
        TBool -> SomeExpr SBool (TVar SBool x)
        TBV w -> withSomeSNat w (\s -> SomeExpr (SBV s) (TVar (SBV s) x))
    go (Lit v)
      | not (validValue v) = Left (InvalidValue v)
    go (Lit (U.VBool b)) = Right (SomeExpr SBool (TLit (VBool b)))
    go (Lit (U.VBV w v)) =
      Right (withSomeSNat (fromIntegral w) (\s -> SomeExpr (SBV s) (TLit (VBV s v))))
    go (Un op a) = do
      SomeExpr s ta <- go a
      case s of
        SBool -> Left ExpectedBV
        SBV _ -> Right (SomeExpr s (TUn op ta))
    go (Bin op a b) = do
      ra <- go a
      rb <- go b
      sameWidth ra rb (\w ta tb -> SomeExpr (SBV w) (TBin op ta tb))
    go (Cmp op a b) = do
      ra <- go a
      rb <- go b
      sameWidth ra rb (\_ ta tb -> SomeExpr SBool (TCmp op ta tb))
    go (Ite c t e) = do
      SomeExpr sc tc <- go c
      rt <- go t
      re <- go e
      case sc of
        SBV w -> Left (ExpectedBool (widthOf w))
        SBool -> sameWidth rt re (\w ta tb -> SomeExpr (SBV w) (TIte tc ta tb))

checkTy :: Ty -> Either TypeError ()
checkTy TBool = Right ()
checkTy ty@(TBV w) = when (w < 1 || w > 64) (Left (InvalidSort ty))

sameWidth ::
  SomeExpr ->
  SomeExpr ->
  (forall w. SNat w -> TExpr ('TBV w) -> TExpr ('TBV w) -> r) ->
  Either TypeError r
sameWidth (SomeExpr (SBV l) ta) (SomeExpr (SBV r) tb) k = case testEquality l r of
  Just Refl -> Right (k l ta tb)
  Nothing -> Left (WidthMismatch (widthOf l) (widthOf r))
sameWidth _ _ _ = Left ExpectedBV
