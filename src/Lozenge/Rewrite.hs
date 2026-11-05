module Lozenge.Rewrite (
  Subst,
  applySubst,
  match,
  unify,
  rewriteOnce,
  NormalForm (..),
  normalise,
)
where

import Control.Applicative ((<|>))
import Control.Monad (foldM, void)
import Data.Foldable (asum, toList)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Traversable (mapAccumL)
import Lozenge.ExprF (ExprF (..), FixRule (..))
import Lozenge.Fix (Fix (..), cata)

type Subst = Map Text (Fix ExprF)

applySubst :: Subst -> Fix ExprF -> Fix ExprF
applySubst s = cata alg
  where
    alg l@(PVar x) = Map.findWithDefault (Fix l) x s
    alg l = Fix l

match :: Fix ExprF -> Fix ExprF -> Maybe Subst
match = go Map.empty
  where
    go s (Fix (PVar x)) t = case Map.lookup x s of
      Nothing -> Just (Map.insert x t s)
      Just bound
        | bound == t -> Just s
        | otherwise -> Nothing
    go s (Fix p) (Fix t)
      | sameLayer p t = foldM (\s' (a, b) -> go s' a b) s (zip (toList p) (toList t))
      | otherwise = Nothing

unify :: Fix ExprF -> Fix ExprF -> Maybe Subst
unify = go Map.empty
  where
    go s a b = step s (applySubst s a) (applySubst s b)

    step s (Fix (PVar x)) (Fix (PVar y)) | x == y = Just s
    step s (Fix (PVar x)) t = bind s x t
    step s t (Fix (PVar x)) = bind s x t
    step s (Fix a) (Fix b)
      | sameLayer a b = foldM (\s' (l, r) -> go s' l r) s (zip (toList a) (toList b))
      | otherwise = Nothing

    bind s x t
      | occurs x t = Nothing
      | otherwise = Just (Map.insert x t (applySubst (Map.singleton x t) <$> s))

occurs :: Text -> Fix ExprF -> Bool
occurs x = cata alg
  where
    alg (PVar y) = x == y
    alg l = or l

sameLayer :: ExprF a -> ExprF b -> Bool
sameLayer a b = void a == void b

rewriteOnce :: [FixRule] -> Fix ExprF -> Maybe (Fix ExprF)
rewriteOnce rules = go
  where
    active = filter (isNothing . frPre) rules

    go t = atRoot t <|> inChild t

    atRoot t = asum [(`applySubst` frRhs r) <$> match (frLhs r) t | r <- active]

    inChild (Fix l) = case mapAccumL firstChild False l of
      (True, l') -> Just (Fix l')
      (False, _) -> Nothing

    firstChild True c = (True, c)
    firstChild False c = maybe (False, c) (True,) (go c)

data NormalForm
  = Done (Fix ExprF)
  | Cycle Int [Fix ExprF]
  | OutOfFuel [Fix ExprF]
  deriving (Eq, Show)

normalise :: Int -> [FixRule] -> Fix ExprF -> ([Text], NormalForm)
normalise fuel rules t0 =
  ([frName r | r <- rules, isJust (frPre r)], go fuel (Set.singleton t0) [t0] t0)
  where
    go left seen trail t = case rewriteOnce rules t of
      Nothing -> Done t
      Just u
        | left <= 0 -> OutOfFuel (reverse trail)
        | u `Set.member` seen -> Cycle (length trail) (reverse (u : trail))
        | otherwise -> go (left - 1) (Set.insert u seen) (u : trail) u
