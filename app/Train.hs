{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Lozenge.Mlp
import Lozenge.TensorEval (InputError)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import Text.Printf (printf)

main :: IO ()
main = do
  dir <- fromMaybe "docs/demo" . listToMaybe <$> getArgs
  createDirectoryIfMissing True dir
  run dir "xor" "XOR: 2-8-1 ReLU MLP, 500 steps at rate 0.1" $
    train @4 @8 0.1 500 xor (initParams @8 1) >>= withAccuracy (accuracy @4 @8 xor)
  let ds = moons 200 7
  run dir "moons" "Two moons, 200 points: 2-16-1 ReLU MLP, 2000 steps at rate 0.1" $
    train @200 @16 0.1 2000 ds (initParams @16 2) >>= withAccuracy (accuracy @200 @16 ds)
  where
    withAccuracy acc (ls, ps) = (,) ls <$> acc ps

run :: FilePath -> Text -> Text -> Either InputError ([Double], Double) -> IO ()
run dir name title result = do
  (losses, acc) <- either (fail . show) pure result
  let path ext = dir <> "/" <> T.unpack name <> "-loss." <> ext
  TIO.writeFile (path "csv") (lossCsv losses)
  TIO.writeFile (path "svg") (lossSvg title losses)
  case (losses, reverse losses) of
    (first : _, final : _) ->
      printf "%s: mean squared error %.3g -> %.3g, accuracy %.1f%%; wrote %s and %s\n" name first final (100 * acc) (path "csv") (path "svg")
    _ -> printf "%s: no losses\n" name
