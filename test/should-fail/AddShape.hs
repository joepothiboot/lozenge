{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module AddShape (bad) where

import Lozenge.Tensor (Tensor (..))

bad :: Tensor '[2, 3]
bad = Add (Var "a") (Var "b" :: Tensor '[3, 2])
