{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}

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

import Data.Set (Set)
import Data.Text (Text)
import Lozenge.Expr (BinOp, CmpOp, UnOp, Value)
import Lozenge.Fix (Fix)
import Lozenge.Rule (Rule, RuleWidth)
import Lozenge.Typecheck (Context, TypeError)
import Lozenge.Typed (SomeExpr, TExpr)

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
fromTyped = error "TODO: fromTyped"

toTyped :: Context -> Fix ExprF -> Either TypeError SomeExpr
toTyped = error "TODO: toTyped"

size :: Fix ExprF -> Int
size = error "TODO: size"

depth :: Fix ExprF -> Int
depth = error "TODO: depth"

vars :: Fix ExprF -> Set Text
vars = error "TODO: vars"

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
ruleToFix = error "TODO: ruleToFix"
