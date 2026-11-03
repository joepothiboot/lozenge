{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Mlp (
  Params,
  Dataset (..),
  predict,
  squaredErrors,
  uniforms,
  initParams,
  xor,
  moons,
  sgdStep,
  train,
  accuracy,
  lossCsv,
  lossSvg,
)
where

import Data.Bits (shiftR)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import GHC.TypeLits (KnownNat, natVal)
import Lozenge.Grad (grad)
import Lozenge.Tensor (Tensor (..))
import Lozenge.TensorEval (InputError, evalTensor)
import Text.Printf (printf)

type Params = Map Text [Double]

data Dataset = Dataset
  { dsPoints :: [Double],
    dsTargets :: [Double]
  }
  deriving (Eq, Show)

predict :: forall n h. (KnownNat n, KnownNat h) => Tensor '[n, 1]
predict = Add (MatMul hidden (Var "w2" :: Tensor '[h, 1])) (MatMul ones (Var "b2"))
  where
    hidden = Relu (Add (MatMul (Var "x" :: Tensor '[n, 2]) (Var "w1" :: Tensor '[2, h])) (MatMul ones (Var "b1")))
    ones = Var "ones" :: Tensor '[n, 1]

squaredErrors :: forall n h. (KnownNat n, KnownNat h) => Tensor '[n, 1]
squaredErrors = Mul d d
  where
    d = Add (predict @n @h) (Var "minus y")

uniforms :: Word64 -> [Double]
uniforms = map unit . drop 1 . iterate (\s -> s * 6364136223846793005 + 1442695040888963407)
  where
    unit s = fromIntegral (s `shiftR` 11) / 2 ^ (53 :: Int)

initParams :: forall h. (KnownNat h) => Word64 -> Params
initParams seed =
  M.fromList [("w1", w1), ("b1", replicate h 0.1), ("w2", w2), ("b2", [0])]
  where
    h = fromIntegral (natVal (Proxy @h))
    us = map (\u -> 2 * u - 1) (uniforms seed)
    w1 = map (* sqrt (6 / 2)) (take (2 * h) us)
    w2 = map (* sqrt (6 / fromIntegral h)) (take h (drop (2 * h) us))

xor :: Dataset
xor = Dataset [0, 0, 0, 1, 1, 0, 1, 1] [0, 1, 1, 0]

moons :: Int -> Word64 -> Dataset
moons n seed = Dataset (concat [[px, py] | (px, py, _) <- pts]) [l | (_, _, l) <- pts]
  where
    pts = take n (zipWith point [0 ..] (triples (uniforms seed)))
    point k (u, a, b)
      | k < n `div` 2 = (cos t + na, sin t + nb, 0)
      | otherwise = (1 - cos t + na, 0.5 - sin t + nb, 1)
      where
        t = pi * u
        na = 0.2 * (a - 0.5)
        nb = 0.2 * (b - 0.5)
    triples (p : q : r : rest) = (p, q, r) : triples rest
    triples _ = []

sgdStep :: Double -> Params -> Map Text [Double] -> Params
sgdStep rate ps gs = M.mapWithKey step ps
  where
    step k p = maybe p (zipWith (\pk gk -> pk - rate * gk) p) (M.lookup k gs)

train :: forall n h. (KnownNat n, KnownNat h) => Double -> Int -> Dataset -> Params -> Either InputError ([Double], Params)
train rate epochs ds = go epochs []
  where
    count = fromIntegral (natVal (Proxy @n))
    go k acc ps = do
      let env = M.union ps (dataInputs ds)
      errs <- evalTensor env (squaredErrors @n @h)
      let loss = sum errs / count
      if k <= 0
        then pure (reverse (loss : acc), ps)
        else do
          g <- grad env (squaredErrors @n @h)
          let ps' = sgdStep (rate / count) ps g
          -- Force the new weights each step, or every step leaves a thunk.
          loss `seq` foldr seq () (concat (M.elems ps')) `seq` go (k - 1) (loss : acc) ps'

accuracy :: forall n h. (KnownNat n, KnownNat h) => Dataset -> Params -> Either InputError Double
accuracy ds ps = do
  out <- evalTensor (M.union ps (dataInputs ds)) (predict @n @h)
  let hits = length (filter id (zipWith (\p y -> (p > 0.5) == (y > 0.5)) out (dsTargets ds)))
  pure (fromIntegral hits / fromIntegral (max 1 (length (dsTargets ds))))

dataInputs :: Dataset -> Params
dataInputs (Dataset pts ys) =
  M.fromList [("x", pts), ("ones", map (const 1) ys), ("minus y", map negate ys)]

lossCsv :: [Double] -> Text
lossCsv ls = T.unlines ("epoch,loss" : zipWith (\i l -> showT i <> "," <> showT l) [0 :: Int ..] ls)

lossSvg :: Text -> [Double] -> Text
lossSvg title ls =
  T.unlines $
    [ "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"400\" viewBox=\"0 0 640 400\" font-family=\"sans-serif\" font-size=\"12\">",
      "<rect width=\"640\" height=\"400\" fill=\"white\"/>",
      label 350 24 "middle" "font-size=\"14\"" title,
      label 350 390 "middle" "" "epoch",
      label 16 195 "middle" "transform=\"rotate(-90 16 195)\"" "mean squared error (log scale)",
      "<path d=\"M70 40 V350 H630\" fill=\"none\" stroke=\"#444\"/>"
    ]
      <> concat [[tick 66 70 (yAt (fromIntegral d)), label 62 (yAt (fromIntegral d) + 4) "end" "" ("1e" <> showT d)] | d <- [lo, lo + step .. hi]]
      <> [ label 70 366 "middle" "" "0",
           label 630 366 "end" "" (showT (max 0 (length ls - 1))),
           "<polyline fill=\"none\" stroke=\"#1f6fb4\" stroke-width=\"2\" points=\"" <> T.unwords (zipWith point [0 :: Int ..] logs) <> "\"/>",
           "</svg>"
         ]
  where
    logs = map (logBase 10 . min 1e300 . max 1e-300) ls
    (lo, hi0) = case logs of
      [] -> (0, 1)
      v : vs -> (floor (foldr min v vs), ceiling (foldr max v vs)) :: (Int, Int)
    hi = max (lo + 1) hi0
    step = max 1 ((hi - lo + 7) `div` 8)
    yAt v = 350 - 310 * (v - fromIntegral lo) / fromIntegral (hi - lo) :: Double
    xAt i = 70 + 560 * fromIntegral i / fromIntegral (max 1 (length ls - 1)) :: Double
    point i v = num (xAt i) <> "," <> num (yAt v)
    tick x0 x1 y = "<line x1=\"" <> num x0 <> "\" y1=\"" <> num y <> "\" x2=\"" <> num x1 <> "\" y2=\"" <> num y <> "\" stroke=\"#444\"/>"
    label :: Double -> Double -> Text -> Text -> Text -> Text
    label x y anchor extra s =
      "<text x=\"" <> num x <> "\" y=\"" <> num y <> "\" text-anchor=\"" <> anchor <> "\" " <> extra <> ">" <> escape s <> "</text>"
    num = T.pack . printf "%.1f"
    escape = T.replace "<" "&lt;" . T.replace "&" "&amp;"

showT :: (Show a) => a -> Text
showT = T.pack . show
