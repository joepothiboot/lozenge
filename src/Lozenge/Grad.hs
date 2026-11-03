module Lozenge.Grad (
  grad,
)
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Lozenge.Tensor (Tensor)
import Lozenge.TensorEval (InputError, Inputs)

grad :: (Ord a, Num a) => Inputs a -> Tensor s -> Either InputError (Map Text [a])
grad = error "TODO: grad"
