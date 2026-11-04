{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ConcatAxisRange (bad) where

import GHC.TypeLits (natSing)
import Lozenge.Tensor (Tensor (..))

-- expect: concat: the axis is out of range for these shapes
bad :: Tensor '[2, 3]
bad = Concat (natSing @2) (Var "a" :: Tensor '[2, 3]) (Var "b" :: Tensor '[2, 3])
