{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ReshapeProduct (bad) where

import Lozenge.Tensor (Tensor (..))

-- expect: Couldn't match type '6' with '4'
bad :: Tensor '[4]
bad = Reshape (Var "a" :: Tensor '[2, 3])
