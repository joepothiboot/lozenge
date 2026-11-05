{-# LANGUAGE OverloadedStrings #-}

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

import Control.Monad (unless, when, (>=>))
import Control.Monad.ST (ST)
import Data.Containers.ListUtils (nubOrd)
import Data.Foldable (for_)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Kind (Type)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.STRef (STRef, modifySTRef', newSTRef, readSTRef, writeSTRef)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Traversable (for)
import Lozenge.Fix (Fix, cata)
import Lozenge.UnionFind (UF, find, makeSet, newUF, parents, union)

type ClassId = Int

type Language f = (Traversable f, Ord (f ClassId), Show (f ClassId))

data EClass f = EClass
  { ecNodes :: Set (f ClassId),
    ecParents :: [(f ClassId, ClassId)]
  }

data EGraph (f :: Type -> Type) s = EGraph
  { egUF :: UF s,
    egHash :: STRef s (Map (f ClassId) ClassId),
    egClasses :: STRef s (IntMap (EClass f)),
    egWorklist :: STRef s [ClassId]
  }

newEGraph :: ST s (EGraph f s)
newEGraph = EGraph <$> newUF <*> newSTRef Map.empty <*> newSTRef IntMap.empty <*> newSTRef []

canonical :: (Language f) => EGraph f s -> f ClassId -> ST s (f ClassId)
canonical g = traverse (find (egUF g))

addNode :: (Language f) => EGraph f s -> f ClassId -> ST s ClassId
addNode g n = do
  node <- canonical g n
  known <- Map.lookup node <$> readSTRef (egHash g)
  case known of
    Just c -> find (egUF g) c
    Nothing -> do
      c <- makeSet (egUF g)
      modifySTRef' (egHash g) (Map.insert node c)
      modifySTRef' (egClasses g) $ \m ->
        foldr
          (IntMap.adjust (\e -> e{ecParents = (node, c) : ecParents e}))
          (IntMap.insert c (EClass (Set.singleton node) []) m)
          node
      pure c

addTerm :: (Language f) => EGraph f s -> Fix f -> ST s ClassId
addTerm g = cata (sequence >=> addNode g)

merge :: (Language f) => EGraph f s -> ClassId -> ClassId -> ST s ()
merge g a b = do
  ra <- find (egUF g) a
  rb <- find (egUF g) b
  when (ra /= rb) $ do
    r <- union (egUF g) ra rb
    let loser = if r == ra then rb else ra
    modifySTRef' (egClasses g) $ \m ->
      IntMap.delete loser (IntMap.insertWith combine r (IntMap.findWithDefault (EClass Set.empty []) loser m) m)
    modifySTRef' (egWorklist g) (r :)
  where
    combine x y = EClass (Set.union (ecNodes x) (ecNodes y)) (ecParents x ++ ecParents y)

rebuild :: (Language f) => EGraph f s -> ST s ()
rebuild g = do
  pending <- readSTRef (egWorklist g)
  unless (null pending) $ do
    writeSTRef (egWorklist g) []
    roots <- traverse (find (egUF g)) pending
    mapM_ (repair g) (nubOrd roots)
    rebuild g

repair :: (Language f) => EGraph f s -> ClassId -> ST s ()
repair g c = do
  r <- find (egUF g) c
  ps <- maybe [] ecParents . IntMap.lookup r <$> readSTRef (egClasses g)
  modifySTRef' (egClasses g) (IntMap.adjust (\e -> e{ecParents = []}) r)
  fresh <- for ps $ \(node, p) -> do
    node' <- canonical g node
    when (node' /= node) (modifySTRef' (egHash g) (Map.delete node))
    known <- Map.lookup node' <$> readSTRef (egHash g)
    for_ known (merge g p)
    p' <- find (egUF g) p
    modifySTRef' (egHash g) (Map.insert node' p')
    pure (node', p')
  root <- find (egUF g) r
  modifySTRef' (egClasses g) (IntMap.adjust (\e -> e{ecParents = Map.toList (Map.fromList fresh) ++ ecParents e}) root)

equiv :: (Language f) => EGraph f s -> ClassId -> ClassId -> ST s Bool
equiv g a b = (==) <$> find (egUF g) a <*> find (egUF g) b

classes :: (Language f) => EGraph f s -> ST s [(ClassId, [f ClassId])]
classes g = do
  m <- readSTRef (egClasses g)
  for (IntMap.toAscList m) $ \(c, e) -> do
    nodes <- traverse (canonical g) (Set.toList (ecNodes e))
    pure (c, Set.toAscList (Set.fromList nodes))

checkInvariants :: (Language f) => EGraph f s -> ST s [Text]
checkInvariants g = do
  cs <- classes g
  resolved <- readSTRef (egHash g) >>= traverse (find (egUF g))
  entries <- for (Map.toList resolved) (\(n, c) -> (,c) <$> canonical g n)
  keys <- IntMap.keys <$> readSTRef (egClasses g)
  ps <- parents (egUF g)
  let owners = Map.fromListWith (++) [(n, [c]) | (c, ns) <- cs, n <- ns]
      roots = [i | (i, p) <- zip [0 ..] ps, i == p]
  pure $
    ["invariant 1: node " <> showT n <> " of class " <> showT c <> " is not in the hash-cons under that class" | (c, ns) <- cs, n <- ns, Map.lookup n resolved /= Just c]
      ++ ["invariant 2: hash-cons entry " <> showT n <> " -> " <> showT c <> " is not a node of that class" | (n, c) <- entries, c `notElem` Map.findWithDefault [] n owners]
      ++ ["invariant 3: node " <> showT n <> " is in classes " <> showT owned | (n, owned@(_ : _ : _)) <- Map.toList owners]
      ++ ["invariant 4: the class map is keyed by " <> showT keys <> ", the roots are " <> showT roots | keys /= roots]

showT :: (Show a) => a -> Text
showT = T.pack . show
