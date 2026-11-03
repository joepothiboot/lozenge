{-# LANGUAGE GADTs #-}

module Lozenge.Graph (
  Shape,
  Op (..),
  NodeId,
  Graph,
  emptyGraph,
  insert,
  graphNodes,
  shapeStep,
  inferShapes,
  lower,
)
where

import Data.IntMap.Strict (IntMap)
import Data.Text (Text)
import Lozenge.Tensor (Tensor)

type Shape = [Int]

data Op a
  = Input Text Shape
  | Add a a
  | Mul a a
  | Relu a
  | MatMul a a
  | Transpose a
  | Reshape Shape a
  | Concat Int a a
  | Slice Int Int Int a
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

type NodeId = Int

data Graph

emptyGraph :: Graph
emptyGraph = error "TODO: emptyGraph"

insert :: Op NodeId -> Graph -> (NodeId, Graph)
insert = error "TODO: insert"

graphNodes :: Graph -> [(NodeId, Op NodeId)]
graphNodes = error "TODO: graphNodes"

shapeStep :: Op Shape -> Either Text Shape
shapeStep = error "TODO: shapeStep"

inferShapes :: Graph -> Either Text (IntMap Shape)
inferShapes = error "TODO: inferShapes"

lower :: Tensor s -> (Graph, NodeId)
lower = error "TODO: lower"
