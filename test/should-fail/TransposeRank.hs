{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module TransposeRank (bad) where

import Lozenge.Tensor (Tensor (..))

-- expect: Couldn't match type: '[4]
bad :: Tensor '[4, 3]
bad = Transpose (Var "a" :: Tensor '[2, 3, 4])
