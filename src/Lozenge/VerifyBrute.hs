{-# LANGUAGE OverloadedStrings #-}

module Lozenge.VerifyBrute (
  Verdict (..),
  Assignment,
  assignmentCap,
  verifyBrute,
  evalSome,
  renderVerdict,
)
where

import Control.Monad (forM_, when)
import Data.Bifunctor (first)
import Data.Either (fromLeft)
import Data.Foldable (traverse_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Lozenge.EvalT (TEnv, checkEnv, evalT)
import Lozenge.Expr (Env, Value (..))
import Lozenge.Rule (Rule (..), instantiate)
import Lozenge.Typecheck (TypeError, checkTy, typecheck)
import Lozenge.Typed (SomeExpr (..), Ty (..), eraseValue, someSort)
import Numeric (showHex)

type Assignment = Env

data Verdict
  = Valid
  | Counterexample Assignment Value Value
  | Unsupported Text
  deriving (Eq, Show)

assignmentCap :: Integer
assignmentCap = 2 ^ (20 :: Int)

verifyBrute :: Int -> Rule -> Verdict
verifyBrute w rule = fromLeft Valid $ do
  r <- maybe (Left (Unsupported ("width " <> showT w <> " is outside 1..64"))) Right (instantiate w rule)

  let vars = ruleVars r
      check = first unsupported . typecheck vars
  traverse_ (first unsupported . checkTy) vars

  lhs <- check (ruleLhs r)
  rhs <- check (ruleRhs r)

  when (someSort lhs /= someSort rhs) (Left (Unsupported "lhs and rhs have different sorts"))

  pre <- traverse check (rulePre r)

  when (any ((/= TBool) . someSort) pre) (Left (Unsupported "the precondition is not Bool"))

  let count = product (assignments <$> Map.elems vars)

  when (count > assignmentCap) (Left (Unsupported (showT count <> " assignments is over the cap of " <> showT assignmentCap)))

  forM_ (traverse domain vars) $ \env -> do
    tenv <- first unsupported (checkEnv vars env)

    when (all ((== VBool True) . evalSome tenv) pre) $ do
      let l = evalSome tenv lhs
          e = evalSome tenv rhs

      when (l /= e) (Left (Counterexample env l e))

unsupported :: TypeError -> Verdict
unsupported = Unsupported . showT

assignments :: Ty -> Integer
assignments TBool = 2
assignments (TBV n) = 2 ^ n

domain :: Ty -> [Value]
domain TBool = [VBool False, VBool True]
domain (TBV n) = VBV (fromIntegral n) <$> [0 .. 2 ^ n - 1]

evalSome :: TEnv -> SomeExpr -> Value
evalSome tenv (SomeExpr _ t) = eraseValue (evalT tenv t)

renderVerdict :: Verdict -> Text
renderVerdict Valid = "valid"
renderVerdict (Unsupported msg) = "unsupported: " <> msg
renderVerdict (Counterexample env l r) = T.intercalate ": " (assignment ++ [sides])
  where
    assignment = [T.intercalate ", " [x <> " = " <> showValue v | (x, v) <- Map.toAscList env] | not (Map.null env)]
    sides = "lhs = " <> showValue l <> ", rhs = " <> showValue r

showValue :: Value -> Text
showValue (VBool True) = "true"
showValue (VBool False) = "false"
showValue (VBV w v) = "0x" <> T.justifyRight ((w + 3) `div` 4) '0' (T.pack (showHex v ""))

showT :: (Show a) => a -> Text
showT = T.pack . show
