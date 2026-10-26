module Lozenge.EvalT (
  TEnv,
  checkEnv,
  evalT,
)
where

import Lozenge.Expr (Env)
import Lozenge.Typecheck (Context, TypeError)
import Lozenge.Typed (TExpr, Value)

newtype TEnv = TEnv Env
  deriving (Show)

checkEnv :: Context -> Env -> Either TypeError TEnv
checkEnv = error "TODO: checkEnv"

evalT :: TEnv -> TExpr t -> Value t
evalT = error "TODO: evalT"
