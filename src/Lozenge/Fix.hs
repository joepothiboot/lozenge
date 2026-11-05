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
cata alg (Fix l) = alg (cata alg <$> l)

ana :: (Functor f) => (a -> f a) -> a -> Fix f
ana coalg = Fix . fmap (ana coalg) . coalg

para :: (Functor f) => (f (Fix f, a) -> a) -> Fix f -> a
para alg (Fix l) = alg ((\t -> (t, para alg t)) <$> l)
