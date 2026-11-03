module Lozenge.EGraph (
  ClassId,
  Language,
  EGraph,
  newEGraph,
  addNode,
  addTerm,
  merge,
  rebuild,
  equiv,
  classes,
  checkInvariants,
)
where

import Control.Monad.ST (ST)
import Data.Kind (Type)
import Data.Text (Text)
import Lozenge.Fix (Fix)

type ClassId = Int


type Language f = (Traversable f, Ord (f ClassId), Show (f ClassId))

data EGraph (f :: Type -> Type) s

newEGraph :: ST s (EGraph f s)
newEGraph = error "TODO: newEGraph"

addNode :: (Language f) => EGraph f s -> f ClassId -> ST s ClassId
addNode = error "TODO: addNode"

addTerm :: (Language f) => EGraph f s -> Fix f -> ST s ClassId
addTerm = error "TODO: addTerm"

merge :: (Language f) => EGraph f s -> ClassId -> ClassId -> ST s ()
merge = error "TODO: merge"

rebuild :: (Language f) => EGraph f s -> ST s ()
rebuild = error "TODO: rebuild"

equiv :: (Language f) => EGraph f s -> ClassId -> ClassId -> ST s Bool
equiv = error "TODO: equiv"

classes :: (Language f) => EGraph f s -> ST s [(ClassId, [f ClassId])]
classes = error "TODO: classes"

checkInvariants :: (Language f) => EGraph f s -> ST s [Text]
checkInvariants = error "TODO: checkInvariants"
