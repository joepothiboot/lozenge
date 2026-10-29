module Lozenge.EMatch (
  ClassSubst,
  ematch,
)
where

import Control.Monad.ST (ST)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Lozenge.EGraph (ClassId, EGraph)
import Lozenge.ExprF (ExprF)
import Lozenge.Fix (Fix)

type ClassSubst = Map Text ClassId

ematch :: EGraph s -> Fix ExprF -> ST s [(ClassId, ClassSubst)]
ematch = error "TODO: ematch"
