{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Lozenge.SymExec (
  Cond,
  andC,
  notC,
  Union (..),
  Mergeable (..),
  merge,
  Stmt (..),
  Program,
  Env (..),
  subst,
  symExec,
)
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Lozenge.Typed (TExpr, Ty (..))

type Cond = TExpr 'TBool

andC :: Cond -> Cond -> Cond
andC = error "TODO: andC"

notC :: Cond -> Cond
notC = error "TODO: notC"

newtype Union a = Union {unUnion :: [(Cond, a)]}
  deriving (Show)

instance Functor Union where
  fmap = error "TODO: fmap @Union"

instance Applicative Union where
  pure = error "TODO: pure @Union"
  (<*>) = error "TODO: <*> @Union"

instance Monad Union where
  (>>=) = error "TODO: >>= @Union"

class Mergeable a where
  mrgIte :: Cond -> a -> a -> a

instance Mergeable (TExpr ('TBV w)) where
  mrgIte = error "TODO: mrgIte @BV"

instance Mergeable (TExpr 'TBool) where
  mrgIte = error "TODO: mrgIte @Bool"

instance Mergeable (Env w) where
  mrgIte = error "TODO: mrgIte @Env"

merge :: (Mergeable a) => Union a -> Union a
merge = error "TODO: merge"

data Stmt w
  = Assign Text (TExpr ('TBV w))
  | If Cond [Stmt w] [Stmt w]
  | Assert Cond
  deriving (Show)

type Program w = [Stmt w]

data Env w = Env
  { envVars :: Map Text (TExpr ('TBV w)),
    envOk :: Cond
  }
  deriving (Show)

subst :: Map Text (TExpr ('TBV w)) -> TExpr t -> TExpr t
subst = error "TODO: subst"

symExec :: Program w -> Union (Env w)
symExec = error "TODO: symExec"
