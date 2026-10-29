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

import Data.Map.Strict (Map)
import Data.Text (Text)
import Lozenge.ExprF (ExprF, FixRule)
import Lozenge.Fix (Fix)

type Subst = Map Text (Fix ExprF)

applySubst :: Subst -> Fix ExprF -> Fix ExprF
applySubst = error "TODO: applySubst"

match :: Fix ExprF -> Fix ExprF -> Maybe Subst
match = error "TODO: match"

unify :: Fix ExprF -> Fix ExprF -> Maybe Subst
unify = error "TODO: unify"

rewriteOnce :: [FixRule] -> Fix ExprF -> Maybe (Fix ExprF)
rewriteOnce = error "TODO: rewriteOnce"

data NormalForm
  = Done (Fix ExprF)
  | Cycle Int [Fix ExprF]
  | OutOfFuel [Fix ExprF]
  deriving (Eq, Show)

normalise :: Int -> [FixRule] -> Fix ExprF -> ([Text], NormalForm)
normalise = error "TODO: normalise"
