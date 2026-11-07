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

import Control.Monad (ap, foldM)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Type.Equality (testEquality, (:~:) (Refl))
import GHC.TypeLits (SNat, natSing)
import Lozenge.Expr (CmpOp (Eq))
import Lozenge.Typed (SingTy (..), TExpr (..), Ty (..), Value (..))

type Cond = TExpr 'TBool

true :: Cond
true = TLit (VBool True)

one, zero :: TExpr ('TBV 1)
one = TLit (VBV natSing 1)
zero = TLit (VBV natSing 0)

toBit :: Cond -> TExpr ('TBV 1)
toBit c = TIte c one zero

fromBit :: TExpr ('TBV 1) -> Cond
fromBit b = TCmp Eq b one

andC :: Cond -> Cond -> Cond
andC (TLit (VBool True)) c = c
andC c (TLit (VBool True)) = c
andC a b = fromBit (TIte a (toBit b) zero)

notC :: Cond -> Cond
notC c = fromBit (TIte c zero one)

orC :: Cond -> Cond -> Cond
orC a b = notC (andC (notC a) (notC b))

newtype Union a = Union {unUnion :: [(Cond, a)]}
  deriving (Show)

instance Functor Union where
  fmap f (Union es) = Union (map (fmap f) es)

instance Applicative Union where
  pure a = Union [(true, a)]
  (<*>) = ap

instance Monad Union where
  Union es >>= f = Union [(andC g h, b) | (g, a) <- es, (h, b) <- unUnion (f a)]

class Mergeable a where
  mrgIte :: Cond -> a -> a -> a

instance Mergeable (TExpr ('TBV w)) where
  mrgIte = TIte

instance Mergeable (TExpr 'TBool) where
  mrgIte c t e = fromBit (TIte c (toBit t) (toBit e))

instance Mergeable (Env w) where
  mrgIte c l r = Env vars (mrgIte c (envOk l) (envOk r))
    where
      vars =
        Map.mergeWithKey
          (\_ a b -> Just (mrgIte c a b))
          (Map.mapWithKey (\x a -> mrgIte c a (input x a)))
          (Map.mapWithKey (\x b -> mrgIte c (input x b) b))
          (envVars l)
          (envVars r)

input :: Text -> TExpr ('TBV w) -> TExpr ('TBV w)
input x e = TVar (SBV (bvSing e)) x

bvSing :: TExpr ('TBV w) -> SNat w
bvSing (TVar (SBV w) _) = w
bvSing (TLit (VBV w _)) = w
bvSing (TUn _ a) = bvSing a
bvSing (TBin _ a _) = bvSing a
bvSing (TIte _ a _) = bvSing a

merge :: (Mergeable a) => Union a -> Union a
merge (Union []) = Union []
merge (Union (e : es)) = Union [go e es]
  where
    go entry [] = entry
    go (g, v) (n : ns) =
      let (gr, vr) = go n ns
       in (orC g gr, mrgIte g v vr)

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
subst m e@(TVar (SBV w) x) = case Map.lookup x m of
  Just v | Just Refl <- testEquality (bvSing v) w -> v
  _ -> e
subst _ e@(TVar SBool _) = e
subst _ e@(TLit _) = e
subst m (TUn op a) = TUn op (subst m a)
subst m (TBin op a b) = TBin op (subst m a) (subst m b)
subst m (TCmp op a b) = TCmp op (subst m a) (subst m b)
subst m (TIte c t e) = TIte (subst m c) (subst m t) (subst m e)

symExec :: Program w -> Union (Env w)
symExec = foldM step (Env Map.empty true)

step :: Env w -> Stmt w -> Union (Env w)
step env (Assign x e) = pure env{envVars = Map.insert x (subst (envVars env) e) (envVars env)}
step env (Assert c) = pure env{envOk = andC (envOk env) (subst (envVars env) c)}
step env (If c t e) = Union [(c', (env, t)), (notC c', (env, e))] >>= uncurry (foldM step)
  where
    c' = subst (envVars env) c
