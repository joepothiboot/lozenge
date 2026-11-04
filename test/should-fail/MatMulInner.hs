{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module MatMulInner (bad) where

import Lozenge.Tensor (Tensor (..))

-- expect: Couldn't match type '4' with '3'
bad :: Tensor '[2, 5]
bad = MatMul (Var "a" :: Tensor '[2, 3]) (Var "b" :: Tensor '[4, 5])
