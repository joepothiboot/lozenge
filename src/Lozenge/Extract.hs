module Lozenge.Extract (
  CostFn,
  astSize,
  shiftsAreCheap,
  extract,
)
where

import Control.Monad (filterM)
import Control.Monad.ST (ST)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (sortOn)
import Data.Maybe (listToMaybe, mapMaybe)
import Lozenge.EGraph (ClassId, EGraph, Language, classes, equiv)
import Lozenge.Expr (BinOp (..))
import Lozenge.ExprF (ExprF (..))
import Lozenge.Fix (Fix, ana)

type CostFn f c = f c -> c

astSize :: CostFn ExprF Int
astSize = (1 +) . sum

shiftsAreCheap :: CostFn ExprF Int
shiftsAreCheap n = own n + sum n
  where
    own (BinF Shl _ _) = 1
    own (BinF Lshr _ _) = 1
    own (BinF Mul _ _) = 4
    own (VarF _) = 1
    own (PVar _) = 1
    own (LitF _) = 1
    own _ = 2

extract :: (Language f, Ord c) => CostFn f c -> EGraph f s -> ClassId -> ST s (Fix f)
extract cost g c = do
  cs <- classes g
  roots <- filterM (equiv g c . fst) cs
  let best = bestNodes cost cs
      node i = maybe (error "extract: a class id this graph did not issue") snd (IntMap.lookup i best)

  pure (ana node (maybe c fst (listToMaybe roots)))

bestNodes :: (Language f, Ord c) => CostFn f c -> [(ClassId, [f ClassId])] -> IntMap (c, f ClassId)
bestNodes cost cs = go IntMap.empty
  where
    go best
      | fmap fst next == fmap fst best = next
      | otherwise = go next
      where
        next = IntMap.fromList [(c, b) | (c, ns) <- cs, b <- take 1 (sortOn fst (mapMaybe (priced best) ns))]
    priced best n = (\l -> (cost l, n)) <$> traverse (\i -> fst <$> IntMap.lookup i best) n
