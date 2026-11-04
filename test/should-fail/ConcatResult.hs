{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ConcatResult (bad) where

import GHC.TypeLits (natSing)
import Lozenge.Tensor (Tensor (..))

-- expect: Couldn't match type '6' with '5'
bad :: Tensor '[5, 3]
bad = Concat (natSing @0) (Var "a" :: Tensor '[2, 3]) (Var "b" :: Tensor '[4, 3])
