module Lozenge.Eval (
  EvalError (..),
  eval,
)
where

import Data.Bits (shiftL, shiftR, xor, (.&.), (.|.))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Lozenge.Expr (BinOp (..), CmpOp (..), Env, Expr (..), UnOp (..), Value (..), validValue)

data EvalError
  = UnboundVar Text
  | ExpectedBV
  | ExpectedBool Int
  | WidthMismatch Int Int
  | InvalidValue Value
  deriving (Eq, Show)

eval :: Env -> Expr -> Either EvalError Value
eval env = go
  where
    go (Var x) = maybe (Left (UnboundVar x)) checked (Map.lookup x env)
    go (Lit v) = checked v
    go (Un op a) = do
      va <- go a
      (w, x) <- asBV va
      pure (VBV w (unOp op w x))
    go (Bin op a b) = do
      va <- go a
      vb <- go b
      (w, x, y) <- sameWidth va vb
      pure (VBV w (binOp op w x y))
    go (Cmp op a b) = do
      va <- go a
      vb <- go b
      (w, x, y) <- sameWidth va vb
      pure (VBool (cmpOp op w x y))
    go (Ite c t e) = do
      vc <- go c
      vt <- go t
      ve <- go e
      cond <- asBool vc
      (w, x, y) <- sameWidth vt ve
      pure (VBV w (if cond then x else y))

checked :: Value -> Either EvalError Value
checked v
  | validValue v = Right v
  | otherwise = Left (InvalidValue v)

asBV :: Value -> Either EvalError (Int, Integer)
asBV (VBV w x) = Right (w, x)
asBV (VBool _) = Left ExpectedBV

asBool :: Value -> Either EvalError Bool
asBool (VBool b) = Right b
asBool (VBV w _) = Left (ExpectedBool w)

sameWidth :: Value -> Value -> Either EvalError (Int, Integer, Integer)
sameWidth va vb = do
  (l, x) <- asBV va
  (r, y) <- asBV vb
  if l == r then Right (l, x, y) else Left (WidthMismatch l r)

modulus :: Int -> Integer
modulus w = 2 ^ w

unOp :: UnOp -> Int -> Integer -> Integer
unOp Not w a = modulus w - 1 - a
unOp Neg w a = (modulus w - a) `mod` modulus w

binOp :: BinOp -> Int -> Integer -> Integer -> Integer
binOp Add w a b = (a + b) `mod` modulus w
binOp Sub w a b = (a - b) `mod` modulus w
binOp Mul w a b = (a * b) `mod` modulus w
binOp And _ a b = a .&. b
binOp Or _ a b = a .|. b
binOp Xor _ a b = a `xor` b
binOp Shl w a b
  | b >= toInteger w = 0
  | otherwise = (a `shiftL` fromInteger b) `mod` modulus w
binOp Lshr w a b
  | b >= toInteger w = 0
  | otherwise = a `shiftR` fromInteger b

cmpOp :: CmpOp -> Int -> Integer -> Integer -> Bool
cmpOp Eq _ a b = a == b
cmpOp Ult _ a b = a < b
cmpOp Slt w a b = signed w a < signed w b

signed :: Int -> Integer -> Integer
signed w v
  | v < modulus (w - 1) = v
  | otherwise = v - modulus w
