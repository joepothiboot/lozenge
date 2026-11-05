{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.ExprF (
  ExprF (..),
  fromTyped,
  toTyped,
  size,
  depth,
  vars,
  FixRule (..),
  ruleToFix,
)
where

import Control.Monad (when)
import Data.Bifunctor (first)
import Data.Foldable (fold)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Lozenge.Expr (BinOp, CmpOp, Expr (..), UnOp, Value)
import Lozenge.Fix (Fix (..), ana, cata)
import Lozenge.Rule (Rule (..), RuleWidth)
import Lozenge.Typecheck (Context, TypeError, typecheck)
import Lozenge.Typed (SomeExpr (..), TExpr, Ty (..), erase, someSort)

data ExprF r
  = VarF Text
  | PVar Text
  | LitF Value
  | UnF UnOp r
  | BinF BinOp r r
  | CmpF CmpOp r r
  | IteF r r r
  deriving stock (Functor, Foldable, Traversable, Eq, Ord, Show)

fromTyped :: TExpr t -> Fix ExprF
fromTyped = ana layer . erase
  where
    layer (Var x) = VarF x
    layer (Lit v) = LitF v
    layer (Un op a) = UnF op a
    layer (Bin op a b) = BinF op a b
    layer (Cmp op a b) = CmpF op a b
    layer (Ite c t e) = IteF c t e

toTyped :: Context -> Fix ExprF -> Either TypeError SomeExpr
toTyped ctx = typecheck ctx . cata alg
  where
    alg (VarF x) = Var x
    alg (PVar x) = Var x
    alg (LitF v) = Lit v
    alg (UnF op a) = Un op a
    alg (BinF op a b) = Bin op a b
    alg (CmpF op a b) = Cmp op a b
    alg (IteF c t e) = Ite c t e

size :: Fix ExprF -> Int
size = cata ((1 +) . sum)

depth :: Fix ExprF -> Int
depth = cata ((1 +) . foldr max 0)

vars :: Fix ExprF -> Set Text
vars = cata alg
  where
    alg (VarF x) = Set.singleton x
    alg (PVar x) = Set.singleton x
    alg l = fold l

data FixRule = FixRule
  { frName :: Text,
    frWidth :: RuleWidth,
    frVars :: Context,
    frLhs :: Fix ExprF,
    frRhs :: Fix ExprF,
    frPre :: Maybe (Fix ExprF)
  }
  deriving stock (Eq, Show)

ruleToFix :: Rule -> Either Text FixRule
ruleToFix r = do
  lhs <- check (ruleLhs r)
  rhs <- check (ruleRhs r)

  when (someSort lhs /= someSort rhs) (Left "lhs and rhs have different sorts")

  pre <- traverse check (rulePre r)

  when (any ((/= TBool) . someSort) pre) (Left "the precondition is not Bool")

  pure
    FixRule
      { frName = ruleName r,
        frWidth = ruleWidth r,
        frVars = ruleVars r,
        frLhs = patternOf lhs,
        frRhs = patternOf rhs,
        frPre = patternOf <$> pre
      }
  where
    check = first (T.pack . show) . typecheck (ruleVars r)

patternOf :: SomeExpr -> Fix ExprF
patternOf (SomeExpr _ t) = cata alg (fromTyped t)
  where
    alg (VarF x) = Fix (PVar x)
    alg l = Fix l
