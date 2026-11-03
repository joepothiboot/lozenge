{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module TensorPrograms (Prog (..), programs, inputSizes, genInputs) where

import Data.Map.Strict qualified as M
import Data.Text (Text)
import GHC.TypeLits (natSing)
import Lozenge.Tensor
import Lozenge.TensorEval (Inputs)
import Test.QuickCheck (Gen, chooseInteger, vectorOf)

data Prog where
  Prog :: (KnownShape s) => String -> Tensor s -> Prog

x, x' :: Tensor '[2, 3]
x = Var "x"
x' = Var "x'"

y, y' :: Tensor '[3, 4]
y = Var "y"
y' = Var "y'"

z, z' :: Tensor '[4, 2]
z = Var "z"
z' = Var "z'"

programs :: [Prog]
programs =
  [ Prog "x y + x y'" (Add (MatMul x y) (MatMul x y')),
    Prog "x y + x' y" (Add (MatMul x y) (MatMul x' y)),
    Prog "transpose (transpose (x + x'))" (Transpose (Transpose (Add x x'))),
    Prog "(x + x') * (x + x)" (Mul (Add x x') (Add x x)),
    Prog "transpose z + transpose z'" (Add (Transpose z) (Transpose z')),
    Prog "slice (concat x x')" (Slice (natSing @1) (natSing @1) (natSing @3) (Concat (natSing @1) x x')),
    Prog "reshape, transpose, matmul" (Add (MatMul (Transpose (Reshape @'[3, 2] (Mul x x'))) y) (MatMul x y')),
    Prog "reshape (reshape x)" (Reshape @'[6] (Reshape @'[3, 2] x)),
    Prog "x" x,
    Prog "relu (x y + x y')" (Relu (Add (MatMul x y) (MatMul x y'))),
    Prog "relu (x + x') * x" (Mul (Relu (Add x x')) x)
  ]

-- | The inputs every program reads from, with their lengths.
inputSizes :: [(Text, Int)]
inputSizes = [("x", 6), ("x'", 6), ("y", 12), ("y'", 12), ("z", 8), ("z'", 8)]

genInputs :: Gen (Inputs Integer)
genInputs =
  M.fromList
    <$> traverse
      (\(name, len) -> (name,) <$> vectorOf len (chooseInteger (-5, 5)))
      inputSizes
