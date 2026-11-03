{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoStarIsType #-}

module Lozenge.Tensor (
  Tensor (..),
  KnownShape (..),
  Product,
  ConcatAt,
  SliceAt,
)
where

import Data.Kind (Type)
import Data.Text (Text)
import Data.Type.Bool (If)
import GHC.TypeLits (ErrorMessage (..), KnownNat, Nat, SNat, TypeError, type (*), type (+), type (-), type (<=?))

class KnownShape (s :: [Nat]) where
  shapeVal :: proxy s -> [Int]

instance KnownShape '[] where
  shapeVal = error "TODO: shapeVal '[]"

instance (KnownNat n, KnownShape ns) => KnownShape (n ': ns) where
  shapeVal = error "TODO: shapeVal (n ': ns)"

type family Product (s :: [Nat]) :: Nat where
  Product '[] = 1
  Product (n ': ns) = n * Product ns

type family ConcatAt (ax :: Nat) (s :: [Nat]) (t :: [Nat]) :: [Nat] where
  ConcatAt ax '[] '[] =
    TypeError ('Text "concat: the axis is out of range for these shapes")
  ConcatAt 0 (m ': ns) (n ': ns) = (m + n) ': ns
  ConcatAt 0 s t =
    TypeError ('Text "concat: shapes must agree on every axis except the one joined")
  ConcatAt ax (d ': s) (d ': t) = d ': ConcatAt (ax - 1) s t
  ConcatAt ax s t =
    TypeError ('Text "concat: shapes must agree on every axis except the one joined")

type family SliceAt (ax :: Nat) (start :: Nat) (len :: Nat) (s :: [Nat]) :: [Nat] where
  SliceAt ax start len '[] =
    TypeError ('Text "slice: the axis is out of range for this shape")
  SliceAt 0 start len (d ': ds) =
    If
      (start + len <=? d)
      (len ': ds)
      (TypeError ('Text "slice: start + length is larger than the axis"))
  SliceAt ax start len (d ': ds) = d ': SliceAt (ax - 1) start len ds

data Tensor (s :: [Nat]) :: Type where
  Var :: (KnownShape s) => Text -> Tensor s
  Add :: Tensor s -> Tensor s -> Tensor s
  Mul :: Tensor s -> Tensor s -> Tensor s
  MatMul ::
    (KnownNat m, KnownNat k, KnownNat n) =>
    Tensor '[m, k] ->
    Tensor '[k, n] ->
    Tensor '[m, n]
  Transpose :: (KnownNat m, KnownNat n) => Tensor '[m, n] -> Tensor '[n, m]
  Reshape :: forall t s. (KnownShape t, Product s ~ Product t) => Tensor s -> Tensor t
  Concat ::
    (KnownShape s, KnownShape t) =>
    SNat ax ->
    Tensor s ->
    Tensor t ->
    Tensor (ConcatAt ax s t)
  Slice ::
    (KnownShape s) =>
    SNat ax ->
    SNat start ->
    SNat len ->
    Tensor s ->
    Tensor (SliceAt ax start len s)
