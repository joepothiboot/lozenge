{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Lozenge.TensorEval (
  Inputs,
  InputError (..),
  evalTensor,
)
where

import Data.List (transpose)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import GHC.TypeLits (KnownNat, SNat, fromSNat, natVal)
import Lozenge.Tensor (KnownShape (..), Tensor (..))

type Inputs a = Map Text [a]

data InputError
  = Unbound Text
  | WrongLength Text Int Int
  deriving (Eq, Show)

evalTensor :: (Ord a, Num a) => Inputs a -> Tensor s -> Either InputError [a]
evalTensor env v@(Var name) = case Map.lookup name env of
  Nothing -> Left (Unbound name)
  Just xs
    | actual == expected -> Right xs
    | otherwise -> Left (WrongLength name expected actual)
    where
      expected = product (shapeVal v)
      actual = length xs
evalTensor env (Add a b) = zipWith (+) <$> evalTensor env a <*> evalTensor env b
evalTensor env (Mul a b) = zipWith (*) <$> evalTensor env a <*> evalTensor env b
evalTensor env (Relu a) = map (max 0) <$> evalTensor env a
evalTensor env (Reshape a) = evalTensor env a
evalTensor env (Transpose (a :: Tensor '[m, n])) =
  transposeFlat (dim (Proxy @m)) (dim (Proxy @n)) <$> evalTensor env a
evalTensor env (MatMul (a :: Tensor '[m, k]) (b :: Tensor '[k, n])) =
  matMul <$> evalTensor env a <*> evalTensor env b
  where
    rows = dim (Proxy @m)
    inner = dim (Proxy @k)
    cols = dim (Proxy @n)
    matMul xs ys =
      let columns = chunks cols inner (transposeFlat inner cols ys)
       in [sum (zipWith (*) row col) | row <- chunks rows inner xs, col <- columns]
evalTensor env (Concat ax a b) =
  join <$> evalTensor env a <*> evalTensor env b
  where
    axis = axisVal ax
    blocks = product (take axis (shapeVal a))
    join xs ys =
      concat $
        zipWith
          (<>)
          (chunks blocks (product (drop axis (shapeVal a))) xs)
          (chunks blocks (product (drop axis (shapeVal b))) ys)
evalTensor env (Slice ax start len a) =
  concatMap keep . chunks blocks blockIn <$> evalTensor env a
  where
    axis = axisVal ax
    shape = shapeVal a
    blocks = product (take axis shape)
    blockIn = product (drop axis shape)
    stride = product (drop (axis + 1) shape)
    keep = take (axisVal len * stride) . drop (axisVal start * stride)

dim :: (KnownNat n) => proxy n -> Int
dim = fromInteger . natVal

axisVal :: SNat n -> Int
axisVal = fromInteger . fromSNat

transposeFlat :: Int -> Int -> [a] -> [a]
transposeFlat m n = concat . transpose . chunks m n

chunks :: Int -> Int -> [a] -> [[a]]
chunks count width xs
  | count <= 0 = []
  | otherwise = row : chunks (count - 1) width rest
  where
    (row, rest) = splitAt width xs
