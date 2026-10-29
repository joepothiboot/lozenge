{-# LANGUAGE UndecidableInstances #-}

module Lozenge.Fix (
  Fix (..),
  cata,
  ana,
  para,
)
where

newtype Fix f = Fix (f (Fix f))

deriving instance (Eq (f (Fix f))) => Eq (Fix f)

deriving instance (Ord (f (Fix f))) => Ord (Fix f)

deriving instance (Show (f (Fix f))) => Show (Fix f)

cata :: (Functor f) => (f a -> a) -> Fix f -> a
cata = error "TODO: cata"

ana :: (Functor f) => (a -> f a) -> a -> Fix f
ana = error "TODO: ana"

para :: (Functor f) => (f (Fix f, a) -> a) -> Fix f -> a
para = error "TODO: para"
