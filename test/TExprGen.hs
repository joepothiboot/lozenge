{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module TExprGen (
  WellTyped (..),
  genRule,
  genTExpr,
  genValue,
  genWellTyped,
  shrinkWellTyped,
  testContext,
  tyOf,
  untyped,
  withSing,
)
where

import Data.Map.Strict qualified as Map
import ExprGen (genPayload)
import GHC.TypeNats (Natural, fromSNat, withSomeSNat)
import Lozenge.Expr (Env)
import Lozenge.Expr qualified as U
import Lozenge.Rule (Rule (..), RuleWidth (..))
import Lozenge.Typecheck (Context)
import Lozenge.Typed
import Test.Tasty.QuickCheck hiding (Fixed)

testContext :: Context
testContext =
  Map.fromList [("p", TBool), ("q", TBool), ("b", TBV 1), ("x", TBV 8), ("y", TBV 8), ("z", TBV 64)]

data WellTyped = WellTyped Context SomeExpr Env
  deriving (Show)

genWellTyped :: Gen WellTyped
genWellTyped = do
  ctx <- genContext
  env <- traverse (\ty -> withSing ty (fmap untyped . genValue)) ctx
  ty <- frequency [(1, pure TBool), (3, TBV <$> genWidth ctx)]
  term <- sized $ \n -> withSing ty (\s -> SomeExpr s <$> genTExpr ctx s n)
  pure (WellTyped ctx term env)

genContext :: Gen Context
genContext = do
  names <- sublistOf ["a", "b", "c", "d"]
  Map.fromList . zip names <$> vectorOf (length names) genTy
  where
    genTy = frequency [(1, pure TBool), (3, TBV <$> anyWidth)]

anyWidth :: Gen Natural
anyWidth = frequency [(3, elements [1, 8, 64]), (1, fromIntegral <$> choose (1, 64 :: Int))]

genWidth :: Context -> Gen Natural
genWidth ctx = frequency ([(2, elements ws) | not (null ws)] ++ [(1, anyWidth)])
  where
    ws = [w | TBV w <- Map.elems ctx]

withSing :: Ty -> (forall t. SingTy t -> r) -> r
withSing TBool k = k SBool
withSing (TBV w) k = withSomeSNat w (k . SBV)

tyOf :: SingTy t -> Ty
tyOf SBool = TBool
tyOf (SBV w) = TBV (fromSNat w)

untyped :: Value t -> U.Value
untyped (VBool b) = U.VBool b
untyped (VBV w v) = U.VBV (fromIntegral (fromSNat w)) v

genValue :: SingTy t -> Gen (Value t)
genValue SBool = VBool <$> arbitrary
genValue (SBV w) = VBV w <$> genPayload (fromIntegral (fromSNat w))

genTExpr :: Context -> SingTy t -> Int -> Gen (TExpr t)
genTExpr ctx s n
  | n <= 0 = leaf
  | otherwise = case s of
      SBool -> frequency [(1, leaf), (4, cmp)]
      SBV _ ->
        frequency
          [ (1, leaf),
            (1, TUn <$> arbitraryBoundedEnum <*> sub 2 s),
            (4, TBin <$> arbitraryBoundedEnum <*> sub 2 s <*> sub 2 s),
            (2, TIte <$> sub 3 SBool <*> sub 3 s <*> sub 3 s)
          ]
  where
    sub :: Int -> SingTy u -> Gen (TExpr u)
    sub k s' = genTExpr ctx s' (n `div` k)
    leaf = oneof ((TLit <$> genValue s) : [pure (TVar s x) | (x, ty) <- Map.toList ctx, ty == tyOf s])
    cmp = do
      w <- genWidth ctx
      withSomeSNat w $ \sw -> TCmp <$> arbitraryBoundedEnum <*> sub 2 (SBV sw) <*> sub 2 (SBV sw)

shrinkWellTyped :: WellTyped -> [WellTyped]
shrinkWellTyped (WellTyped ctx (SomeExpr s te) env) =
  [WellTyped ctx (SomeExpr s te') env | te' <- shrinkTExpr te]
    ++ [WellTyped ctx (SomeExpr s te) env' | env' <- shrinkEnv env]

shrinkTExpr :: TExpr t -> [TExpr t]
shrinkTExpr (TVar _ _) = []
shrinkTExpr (TLit v) = TLit <$> shrinkValue v
shrinkTExpr (TUn op a) = a : [TUn op a' | a' <- shrinkTExpr a]
shrinkTExpr (TBin op a b) =
  [a, b] ++ [TBin op a' b | a' <- shrinkTExpr a] ++ [TBin op a b' | b' <- shrinkTExpr b]
shrinkTExpr (TCmp op a b) =
  [TLit (VBool False), TLit (VBool True)]
    ++ [TCmp op a' b | a' <- shrinkTExpr a]
    ++ [TCmp op a b' | b' <- shrinkTExpr b]
shrinkTExpr (TIte c a b) =
  [a, b]
    ++ [TIte c' a b | c' <- shrinkTExpr c]
    ++ [TIte c a' b | a' <- shrinkTExpr a]
    ++ [TIte c a b' | b' <- shrinkTExpr b]

shrinkValue :: Value t -> [Value t]
shrinkValue (VBool b) = [VBool False | b]
shrinkValue (VBV w v) = VBV w <$> shrinkIntegral v

shrinkEnv :: Env -> [Env]
shrinkEnv env = [Map.insert x v' env | (x, v) <- Map.toList env, v' <- shrinkU v]
  where
    shrinkU (U.VBool b) = [U.VBool False | b]
    shrinkU (U.VBV w v) = U.VBV w <$> shrinkIntegral v

genCtx :: Context
genCtx = Map.fromList [("p", TBool), ("x", TBV 4), ("y", TBV 4)]

genRule :: Gen Rule
genRule = do
  ty <- elements [TBool, TBV 4]
  let term = withSing ty (\s -> erase <$> genTExpr genCtx s 4)
  lhs <- term
  rhs <- frequency [(2, pure lhs), (2, pure (commute lhs)), (3, term)]
  pre <- frequency [(2, pure Nothing), (1, Just . erase <$> genTExpr genCtx SBool 2)]
  w <- elements [Fixed, Generic]
  pure (Rule "generated" w genCtx lhs rhs pre)
  where
    commute (U.Bin op a b) | op `elem` [U.Add, U.Mul, U.And, U.Or, U.Xor] = U.Bin op b a
    commute (U.Cmp U.Eq a b) = U.Cmp U.Eq b a
    commute e = e
