{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ConcatAxisRange (bad) where

import GHC.TypeLits (natSing)
import Lozenge.Tensor (Tensor (..))

bad :: Tensor '[2, 3]
bad = Concat (natSing @2) (Var "a" :: Tensor '[2, 3]) (Var "b" :: Tensor '[2, 3])
