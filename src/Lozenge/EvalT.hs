{-# LANGUAGE GADTs #-}

module Lozenge.EvalT (
  TEnv,
  checkEnv,
  evalT,
)
where

import Control.Monad (unless)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Lozenge.Eval (binOp, cmpOp, unOp)
import Lozenge.Expr (Env, validValue)
import Lozenge.Expr qualified as U
import Lozenge.Typecheck (Context, TypeError (..), checkTy)
import Lozenge.Typed (SingTy (..), TExpr (..), Ty (..), Value (..), widthOf)

newtype TEnv = TEnv Env
  deriving (Show)

checkEnv :: Context -> Env -> Either TypeError TEnv
checkEnv ctx env = TEnv <$> Map.traverseWithKey check ctx
  where
    check :: Text -> Ty -> Either TypeError U.Value
    check x ty = do
      checkTy ty
      v <- maybe (Left (UnboundVar x)) Right (Map.lookup x env)
      unless (validValue v) (Left (InvalidValue v))
      case (ty, v) of
        (TBool, U.VBool _) -> Right v
        (TBool, U.VBV w _) -> Left (ExpectedBool w)
        (TBV _, U.VBool _) -> Left ExpectedBV
        (TBV d, U.VBV w _)
          | fromIntegral d == w -> Right v
          | otherwise -> Left (WidthMismatch (fromIntegral d) w)

evalT :: TEnv -> TExpr t -> Value t
evalT (TEnv env) (TVar s x) = readVar s (Map.lookup x env)
evalT _ (TLit v) = v
evalT env (TUn op a) = case evalT env a of
  VBV w x -> VBV w (unOp op (widthOf w) x)
evalT env (TBin op a b) = case (evalT env a, evalT env b) of
  (VBV w x, VBV _ y) -> VBV w (binOp op (widthOf w) x y)
evalT env (TCmp op a b) = case (evalT env a, evalT env b) of
  (VBV w x, VBV _ y) -> VBool (cmpOp op (widthOf w) x y)
evalT env (TIte c t e) = case evalT env c of
  VBool b -> evalT env (if b then t else e)

readVar :: SingTy t -> Maybe U.Value -> Value t
readVar SBool (Just (U.VBool b)) = VBool b
readVar SBool _ = VBool False
readVar (SBV w) (Just (U.VBV n v)) | n == widthOf w = VBV w v
readVar (SBV w) _ = VBV w 0
