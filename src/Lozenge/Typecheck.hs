module Lozenge.Typecheck (
  Context,
  TypeError (..),
  typecheck,
)
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Lozenge.Expr (Expr, Value)
import Lozenge.Typed (SomeExpr, Ty)

type Context = Map Text Ty

data TypeError
  = UnboundVar Text
  | ExpectedBV
  | ExpectedBool Int
  | WidthMismatch Int Int
  | InvalidValue Value
  | InvalidSort Ty
  deriving (Eq, Show)

typecheck :: Context -> Expr -> Either TypeError SomeExpr
typecheck = error "TODO: typecheck"
