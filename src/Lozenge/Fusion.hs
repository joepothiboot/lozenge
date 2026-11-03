module Lozenge.Fusion (
  Buf (..),
  Ew (..),
  Kernel (..),
  Program (..),
  fuse,
  Cost (..),
  programCost,
  kernelWeight,
  totalCost,
)
where

import Data.Text (Text)
import Lozenge.Graph (Graph, NodeId)

data Buf
  = InBuf Int
  | TmpBuf Int
  deriving (Eq, Ord, Show)

data Ew
  = Load Buf
  | EwAdd Ew Ew
  | EwMul Ew Ew
  deriving (Eq, Show)

data Kernel
  = Elementwise Int Ew
  | MatMulK Buf Buf Int Int Int
  | TransposeK Buf Int Int
  | ConcatK Buf Buf Int Int Int
  | SliceK Buf Int Int Int Int
  deriving (Eq, Show)

data Program = Program
  { progInputs :: [(Text, Int)],
    progKernels :: [Kernel],
    progOutput :: Buf
  }
  deriving (Eq, Show)

fuse :: Graph -> NodeId -> Either Text Program
fuse = error "TODO: fuse"

data Cost = Cost
  { costKernels :: Int,
    costTraffic :: Int
  }
  deriving (Eq, Show)

programCost :: Program -> Cost
programCost = error "TODO: programCost"

kernelWeight :: Int
kernelWeight = 1000

totalCost :: Cost -> Int
totalCost = error "TODO: totalCost"
