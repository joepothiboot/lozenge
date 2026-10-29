module Lozenge.EGraph (
  ClassId,
  EGraph,
  newEGraph,
  addNode,
  addTerm,
  merge,
  rebuild,
  equiv,
  checkInvariants,
)
where

import Control.Monad.ST (ST)
import Data.Text (Text)
import Lozenge.ExprF (ExprF)
import Lozenge.Fix (Fix)

type ClassId = Int

data EGraph s

newEGraph :: ST s (EGraph s)
newEGraph = error "TODO: newEGraph"

addNode :: EGraph s -> ExprF ClassId -> ST s ClassId
addNode = error "TODO: addNode"

addTerm :: EGraph s -> Fix ExprF -> ST s ClassId
addTerm = error "TODO: addTerm"

merge :: EGraph s -> ClassId -> ClassId -> ST s ()
merge = error "TODO: merge"

rebuild :: EGraph s -> ST s ()
rebuild = error "TODO: rebuild"

equiv :: EGraph s -> ClassId -> ClassId -> ST s Bool
equiv = error "TODO: equiv"

checkInvariants :: EGraph s -> ST s [Text]
checkInvariants = error "TODO: checkInvariants"
