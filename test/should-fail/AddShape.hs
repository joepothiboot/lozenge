{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module AddShape (bad) where

import Lozenge.Tensor (Tensor (..))

-- expect: Couldn't match type '3' with '2'
bad :: Tensor '[2, 3]
bad = Add (Var "a") (Var "b" :: Tensor '[3, 2])
