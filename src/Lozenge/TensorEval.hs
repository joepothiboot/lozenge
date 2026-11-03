module Lozenge.TensorEval (
  Inputs,
  InputError (..),
  evalTensor,
)
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Lozenge.Tensor (Tensor)

type Inputs a = Map Text [a]

data InputError
  = Unbound Text
  | WrongLength Text Int Int
  deriving (Eq, Show)

evalTensor :: (Ord a, Num a) => Inputs a -> Tensor s -> Either InputError [a]
evalTensor = error "TODO: evalTensor"
