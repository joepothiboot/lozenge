{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ConcatOffAxis (bad) where

import GHC.TypeLits (natSing)
import Lozenge.Tensor (Tensor (..))

bad :: Tensor '[4, 3]
bad = Concat (natSing @0) (Var "a" :: Tensor '[2, 3]) (Var "b" :: Tensor '[2, 4])
