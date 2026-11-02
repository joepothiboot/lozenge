{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module SliceBounds (bad) where

import GHC.TypeLits (natSing)
import Lozenge.Tensor (Tensor (..))

bad :: Tensor '[2, 2]
bad = Slice (natSing @1) (natSing @2) (natSing @2) (Var "a" :: Tensor '[2, 3])
