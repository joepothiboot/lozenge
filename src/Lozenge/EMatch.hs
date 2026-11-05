module Lozenge.EMatch (
  ClassSubst,
  ematch,
)
where

import Control.Monad (foldM, guard)
import Control.Monad.ST (ST)
import Data.Containers.ListUtils (nubOrd)
import Data.Foldable (toList)
import Data.Functor (void)
import Data.IntMap.Strict qualified as IntMap
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Lozenge.EGraph (ClassId, EGraph, classes)
import Lozenge.ExprF (ExprF (..))
import Lozenge.Fix (Fix (..))

type ClassSubst = Map Text ClassId

ematch :: EGraph ExprF s -> Fix ExprF -> ST s [(ClassId, ClassSubst)]
ematch g pat = do
  cs <- classes g
  let table = IntMap.fromList cs
      go (Fix (PVar x)) c s = case Map.lookup x s of
        Nothing -> [Map.insert x c s]
        Just bound -> [s | bound == c]
      go (Fix l) c s = do
        n <- IntMap.findWithDefault [] c table
        guard (void n == void l)
        foldM (\s' (p, child) -> go p child s') s (zip (toList l) (toList n))

  pure (nubOrd [(c, s) | (c, _) <- cs, s <- go pat c Map.empty])
