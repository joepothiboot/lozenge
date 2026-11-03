module Lozenge.Extract (
  CostFn,
  astSize,
  shiftsAreCheap,
  extract,
)
where

import Control.Monad.ST (ST)
import Lozenge.EGraph (ClassId, EGraph, Language)
import Lozenge.ExprF (ExprF)
import Lozenge.Fix (Fix)

type CostFn f c = f c -> c

astSize :: CostFn ExprF Int
astSize = error "TODO: astSize"

shiftsAreCheap :: CostFn ExprF Int
shiftsAreCheap = error "TODO: shiftsAreCheap"

extract :: (Language f, Ord c) => CostFn f c -> EGraph f s -> ClassId -> ST s (Fix f)
extract = error "TODO: extract"
