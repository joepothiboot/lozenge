{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module SliceAxisRange (bad) where

import GHC.TypeLits (natSing)
import Lozenge.Tensor (Tensor (..))

-- expect: slice: the axis is out of range for this shape
bad :: Tensor '[5, 1]
bad = Slice (natSing @1) (natSing @0) (natSing @1) (Var "a" :: Tensor '[5])
