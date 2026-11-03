{-# LANGUAGE OverloadedStrings #-}

module Lozenge.TensorOpt (
  Rhs (..),
  Snapshot,
  TensorRule (..),
  tensorRules,
  transposeTranspose,
  transposeMatMul,
  transposeAdd,
  factorLeft,
  factorRight,
  reshapeReshape,
  Costed (..),
  localCost,
  optimise,
)
where

import Data.IntMap.Strict (IntMap)
import Data.Text (Text)
import Lozenge.EGraph (ClassId)
import Lozenge.Extract (CostFn)
import Lozenge.Graph (Graph, NodeId, Op, Shape)

data Rhs
  = Class ClassId
  | Node (Op Rhs)
  deriving (Eq, Ord, Show)

type Snapshot = IntMap [Op ClassId]

data TensorRule = TensorRule
  { ruleName :: Text,
    ruleApply :: Snapshot -> Op ClassId -> [Rhs]
  }

tensorRules :: [TensorRule]
tensorRules = [transposeTranspose, transposeMatMul, transposeAdd, factorLeft, factorRight, reshapeReshape]

transposeTranspose :: TensorRule
transposeTranspose = TensorRule "transpose-transpose" (error "TODO: transposeTranspose")

transposeMatMul :: TensorRule
transposeMatMul = TensorRule "transpose-matmul" (error "TODO: transposeMatMul")

transposeAdd :: TensorRule
transposeAdd = TensorRule "transpose-add" (error "TODO: transposeAdd")

factorLeft :: TensorRule
factorLeft = TensorRule "factor-left" (error "TODO: factorLeft")

factorRight :: TensorRule
factorRight = TensorRule "factor-right" (error "TODO: factorRight")

reshapeReshape :: TensorRule
reshapeReshape = TensorRule "reshape-reshape" (error "TODO: reshapeReshape")

data Costed
  = Costed Int Shape
  | IllShaped
  deriving (Eq, Ord, Show)

localCost :: CostFn Op Costed
localCost = error "TODO: localCost"

optimise :: Int -> Graph -> NodeId -> (Graph, NodeId)
optimise = error "TODO: optimise"
