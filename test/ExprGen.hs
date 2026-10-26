{-# LANGUAGE OverloadedStrings #-}

module ExprGen (genExpr, shrinkExpr, testEnv) where

import Data.Map.Strict qualified as Map
import Lozenge.Expr
import Test.Tasty.QuickCheck

testEnv :: Env
testEnv =
  Map.fromList
    [ ("p", VBool True),
      ("q", VBool False),
      ("b", VBV 1 1),
      ("x", VBV 8 200),
      ("y", VBV 8 7),
      ("z", VBV 64 (2 ^ (64 :: Int) - 1))
    ]

data Sort = SBool | SBV Int

genExpr :: Gen Expr
genExpr = sized $ \n -> do
  sloppy <- frequency [(3, pure False), (1, pure True)]
  genSort >>= go sloppy n

genSort :: Gen Sort
genSort = frequency [(1, pure SBool), (4, SBV <$> elements [1, 8, 64]), (1, SBV <$> choose (1, 64))]

go :: Bool -> Int -> Sort -> Gen Expr
go sloppy n want0 = do
  want <- if sloppy then genSort else pure want0
  let sub = go sloppy (n `div` 2)
      sub3 = go sloppy (n `div` 3)
  if n <= 0
    then leaf sloppy want
    else case want of
      SBool ->
        frequency
          [ (1, leaf sloppy SBool),
            (3, genWidth >>= \w -> Cmp <$> arbitraryBoundedEnum <*> sub (SBV w) <*> sub (SBV w))
          ]
      SBV _ ->
        frequency
          [ (1, leaf sloppy want),
            (1, Un <$> arbitraryBoundedEnum <*> sub want),
            (4, Bin <$> arbitraryBoundedEnum <*> sub want <*> sub want),
            (1, Ite <$> sub3 SBool <*> sub3 want <*> sub3 want)
          ]
  where
    genWidth = elements [1, 8, 64]

leaf :: Bool -> Sort -> Gen Expr
leaf sloppy want = oneof (lit : map (pure . Var) (vars ++ ["u" | sloppy]))
  where
    vars = [k | (k, v) <- Map.toList testEnv, sameSort v]
    sameSort v = case (want, v) of
      (SBool, VBool _) -> True
      (SBV w, VBV w' _) -> w == w'
      _ -> False
    lit = case want of
      SBool -> Lit . VBool <$> arbitrary
      SBV w -> Lit . VBV w <$> genPayload w

genPayload :: Int -> Gen Integer
genPayload w =
  oneof
    [ elements [0, 1, top, 2 ^ (w - 1)],
      min top <$> choose (0, toInteger w + 1),
      choose (0, top)
    ]
  where
    top = 2 ^ w - 1

shrinkExpr :: Expr -> [Expr]
shrinkExpr (Var _) = []
shrinkExpr (Lit (VBool b)) = [Lit (VBool False) | b]
shrinkExpr (Lit (VBV w v)) = [Lit (VBV w v') | v' <- shrinkIntegral v]
shrinkExpr (Un op a) = a : [Un op a' | a' <- shrinkExpr a]
shrinkExpr (Bin op a b) = [a, b] ++ [Bin op a' b | a' <- shrinkExpr a] ++ [Bin op a b' | b' <- shrinkExpr b]
shrinkExpr (Cmp op a b) = [a, b] ++ [Cmp op a' b | a' <- shrinkExpr a] ++ [Cmp op a b' | b' <- shrinkExpr b]
shrinkExpr (Ite c t e) =
  [c, t, e]
    ++ [Ite c' t e | c' <- shrinkExpr c]
    ++ [Ite c t' e | t' <- shrinkExpr t]
    ++ [Ite c t e' | e' <- shrinkExpr e]
