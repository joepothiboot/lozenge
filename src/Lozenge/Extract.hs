module Lozenge.Extract (
  CostFn,
  astSize,
  shiftsAreCheap,
  extract,
)
where

import Control.Monad.ST (ST)
import Lozenge.EGraph (ClassId, EGraph)
import Lozenge.ExprF (ExprF)
import Lozenge.Fix (Fix)

type CostFn = ExprF Int -> Int

astSize :: CostFn
astSize = error "TODO: astSize"

shiftsAreCheap :: CostFn
shiftsAreCheap = error "TODO: shiftsAreCheap"

extract :: CostFn -> EGraph s -> ClassId -> ST s (Fix ExprF)
extract = error "TODO: extract"
