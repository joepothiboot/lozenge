{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Saturate (
  CheckedRule,
  checkedRule,
  loadRules,
  Limits (..),
  StopReason (..),
  SatReport (..),
  saturate,
)
where

import Control.Monad (forM_)
import Control.Monad.ST (ST)
import Data.Bifunctor (first)
import Data.Either (partitionEithers)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Tuple (swap)
import Lozenge.EGraph (EGraph, addNode, classes, merge, rebuild)
import Lozenge.EMatch (ClassSubst, ematch)
import Lozenge.Eval (eval)
import Lozenge.Expr (Value (..))
import Lozenge.ExprF (ExprF (..), FixRule (..), ruleToFix, vars)
import Lozenge.Fix (cata)
import Lozenge.Rule (Rule (..), instantiate)
import Lozenge.VerifyBrute (Verdict (..), renderVerdict, verifyBrute)

data CheckedRule = CheckedRule
  { crRule :: Rule,
    crFix :: FixRule
  }

checkedRule :: CheckedRule -> Rule
checkedRule = crRule

loadRules :: Int -> [Rule] -> ([CheckedRule], [(Text, Text)])
loadRules w = swap . partitionEithers . map admit
  where
    admit r = first (ruleName r,) $ case (verifyBrute w r, instantiate w r) of
      (Valid, Just i) -> do
        fx <- ruleToFix i
        if vars (frRhs fx) `Set.isSubsetOf` vars (frLhs fx)
          then Right (CheckedRule i fx)
          else Left "the rhs has a variable the lhs does not bind"
      (v, _) -> Left (renderVerdict v)

data Limits = Limits
  { limIters :: Int,
    limNodes :: Int,
    limMatches :: Int,
    limBan :: Int
  }
  deriving (Eq, Show)

data StopReason
  = Saturated
  | IterLimit
  | NodeLimit
  deriving (Eq, Show)

data SatReport = SatReport
  { satStop :: StopReason,
    satIterations :: Int,
    satNodes :: Int,
    satBanned :: [Text]
  }
  deriving (Eq, Show)

data Sched = Sched
  { schedBans :: Int,
    schedUntil :: Int
  }

saturate :: Limits -> [CheckedRule] -> EGraph ExprF s -> ST s SatReport
saturate lims rules g = loop 0 [(r, Sched 0 0) | r <- rules]
  where
    loop i sched = do
      before <- classes g
      let lits = IntMap.fromList [(c, v) | (c, ns) <- before, LitF v <- ns]
      searched <- traverse (search i lits) sched
      forM_ searched $ \((r, _), found) ->
        forM_ (concat found) $ \(c, s) ->
          build s (frRhs (crFix r)) >>= merge g c
      rebuild g
      after <- classes g
      let next = map fst searched
          iters = i + 1
          hidden = any (isNothing . snd) searched
          report stop = SatReport stop iters (nodes after) [ruleName (crRule r) | (r, s) <- next, schedBans s > 0]
          stopAt
            | counts before == counts after && not hidden = Just Saturated
            | nodes after > limNodes lims = Just NodeLimit
            | iters >= limIters lims = Just IterLimit
            | otherwise = Nothing
      maybe (loop iters next) (pure . report) stopAt

    search i lits (r, s)
      | i < schedUntil s = pure ((r, s), Nothing)
      | otherwise = do
          ms <- ematch g (frLhs (crFix r))
          pure $
            if length ms > limMatches lims * 2 ^ schedBans s
              then ((r, Sched (schedBans s + 1) (i + limBan lims * 2 ^ schedBans s)), Nothing)
              else ((r, s), Just (filter (fires lits r . snd) ms))

    build s = cata alg
      where
        alg (PVar x) | Just c <- Map.lookup x s = pure c
        alg l = sequence l >>= addNode g

    counts cs = (length cs, nodes cs)
    nodes = sum . map (length . snd)

fires :: IntMap Value -> CheckedRule -> ClassSubst -> Bool
fires lits r s =
  all (`Map.member` env) (foldMap vars (frPre (crFix r)))
    && all ((== Right (VBool True)) . eval env) (rulePre (crRule r))
  where
    env = Map.mapMaybe (`IntMap.lookup` lits) s
