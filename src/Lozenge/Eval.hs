module Lozenge.Eval
  ( EvalError (..),
    eval,
  )
where

import Data.Text (Text)
import Lozenge.Expr (Env, Expr, Value)

data EvalError
  = UnboundVar Text
  | ExpectedBV
  | ExpectedBool Int
  | WidthMismatch Int Int
  | InvalidValue Value
  deriving (Eq, Show)

eval :: Env -> Expr -> Either EvalError Value
eval = error "TODO: eval"
