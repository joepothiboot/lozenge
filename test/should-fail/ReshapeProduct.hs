{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ReshapeProduct (bad) where

import Lozenge.Tensor (Tensor (..))

bad :: Tensor '[4]
bad = Reshape (Var "a" :: Tensor '[2, 3])
