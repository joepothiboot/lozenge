{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad.ST (runST)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (showVersion)
import Lozenge.EGraph (addTerm, newEGraph)
import Lozenge.Expr (BinOp (..), CmpOp (..), Expr (..), UnOp (..), Value (..))
import Lozenge.ExprF (ExprF (..), FixRule, ruleToFix, size)
import Lozenge.Extract (astSize, extract)
import Lozenge.Fix (Fix (..))
import Lozenge.Pretty (render)
import Lozenge.Rewrite (NormalForm (..), normalise)
import Lozenge.Rule (Rule (..))
import Lozenge.RuleParse (parseRules)
import Lozenge.Saturate (CheckedRule, Limits (..), SatReport (..), StopReason (..), checkedRule, loadRules, saturate)
import System.Info (arch, compilerName, fullCompilerVersion, os)
import Test.QuickCheck (Gen, chooseInt, elements, frequency, vectorOf)
import Test.QuickCheck.Gen (unGen)
import Test.QuickCheck.Random (mkQCGen)
import Test.Tasty.Bench (bench, bgroup, defaultMain, whnf)
import Text.Megaparsec (errorBundlePretty)
import Text.Printf (printf)

type Term = Fix ExprF

corpus :: FilePath
corpus = "rules/bitvector.rules"

width :: Int
width = 8

fuel :: Int
fuel = 100

limits :: Limits
limits = Limits{limIters = 10, limNodes = 10000, limMatches = 1000, limBan = 2}

maxSearchSize :: Int
maxSearchSize = 5

data Orders = Orders
  { fwdFix, revFix :: [FixRule],
    fwdChecked, revChecked :: [CheckedRule]
  }

main :: IO ()
main = do
  say ("compiler: " <> T.pack (compilerName <> " " <> showVersion fullCompilerVersion <> ", " <> arch <> "-" <> os))
  src <- TIO.readFile corpus
  rules <- either (fail . errorBundlePretty) pure (parseRules corpus src)
  let (checked, refused) = loadRules width rules
      plain = filter (isNothing . rulePre . checkedRule) checked
  fixes <- either (fail . T.unpack) pure (traverse (ruleToFix . checkedRule) plain)
  let orders = Orders fixes (reverse fixes) plain (reverse plain)
  say ("rules: " <> showT (length rules) <> " in the corpus, " <> showT (length refused) <> " refused by loadRules at width " <> showT width <> ", " <> showT (length checked - length plain) <> " with a precondition left out, " <> showT (length plain) <> " used")
  mapM_ (\(name, why) -> say ("  refused " <> name <> ": " <> why)) refused
  say ""
  search orders
  say ""
  sizeTable orders
  say ""
  defaultMain
    [ bgroup
        ("size " <> show n)
        [ bench "greedy" (whnf (sum . map (nfSize . snd . normalise fuel (fwdFix orders))) ts),
          bench "saturation" (whnf (sum . map (size . snd . saturated (fwdChecked orders))) ts)
        ]
    | n <- benchSizes,
      let ts = randomTerms n
    ]

data Verdict
  = NoNormalForm
  | SameGreedy
  | SatDiffers
  | SatNotSmaller
  | SatBeatsOne
  | SatBeatsBoth
  deriving (Eq, Show, Enum, Bounded)

classify :: Orders -> Term -> Verdict
classify o t = case (snd (normalise fuel (fwdFix o) t), snd (normalise fuel (revFix o) t)) of
  (Done f, Done r)
    | f == r -> SameGreedy
    | sf /= sr -> SatDiffers
    | size sf < min (size f) (size r) -> SatBeatsBoth
    | size sf <= min (size f) (size r) && size sf < max (size f) (size r) -> SatBeatsOne
    | otherwise -> SatNotSmaller
  _ -> NoNormalForm
  where
    sf = snd (saturated (fwdChecked o) t)
    sr = snd (saturated (revChecked o) t)

search :: Orders -> IO ()
search o = do
  say ("search: every well-typed term of 1 to " <> showT maxSearchSize <> " nodes over x, y, 0, 1, 2, true, false and the corpus operators; greedy in corpus order and reversed")
  say ""
  say ("| size | terms | " <> T.intercalate " | " (map showT verdicts) <> " |")
  say ("|---|---|" <> T.concat (map (const "---|") verdicts))
  go 1
  where
    verdicts = [minBound .. maxBound] :: [Verdict]
    go n
      | n > maxSearchSize = do
          say ""
          say ("no witness up to " <> showT maxSearchSize <> " nodes: add 2 valid rules to the corpus that create one (see the write-up)")
      | otherwise = do
          let cands = terms n
              vs = map (classify o) cands
              count v = length (filter (== v) vs)
              hits = [t | want <- [SatBeatsBoth, SatBeatsOne], (t, v) <- zip cands vs, v == want]
          say ("| " <> showT n <> " | " <> showT (length cands) <> " | " <> T.intercalate " | " (map (showT . count) verdicts) <> " |")
          case hits of
            t : _ -> say "" >> witness o t
            [] -> go (n + 1)

witness :: Orders -> Term -> IO ()
witness o t = do
  say ("witness: " <> pretty t <> " (" <> showT (size t) <> " nodes)")
  greedyRun "greedy, corpus order" (fwdFix o)
  greedyRun "greedy, reversed" (revFix o)
  satRun "saturation, corpus order" (fwdChecked o)
  satRun "saturation, reversed" (revChecked o)
  where
    greedyRun label rs = do
      let (fired, nf) = normalise fuel rs t
      say ("  " <> label <> ": " <> T.intercalate ", " fired)
      say ("    => " <> showNF nf)
    satRun label rs = do
      let (r, e) = saturated rs t
      say ("  " <> label <> ": " <> showT (satStop r) <> " after " <> showT (satIterations r) <> " iterations, " <> showT (satNodes r) <> " nodes")
      say ("    => " <> pretty e <> " (" <> showT (size e) <> " nodes)")

terms :: Int -> [Term]
terms n = bvTerms n ++ boolTerms n

bvTerms, boolTerms :: Int -> [Term]
bvTerms 1 = [var "x", var "y"] ++ map bv [0, 1, 2]
bvTerms n =
  [Fix (UnF op t) | op <- [Not, Neg], t <- bvTerms (n - 1)]
    ++ [Fix (BinF op l r) | op <- [Add, Sub, Mul, And, Or, Xor, Shl, Lshr], (i, j) <- splits (n - 1), l <- bvTerms i, r <- bvTerms j]
    ++ [Fix (IteF c l r) | [i, j, k] <- splits3 (n - 1), c <- boolTerms i, l <- bvTerms j, r <- bvTerms k]
boolTerms 1 = map (Fix . LitF . VBool) [True, False]
boolTerms n = [Fix (CmpF op l r) | op <- [Eq, Ult, Slt], (i, j) <- splits (n - 1), l <- bvTerms i, r <- bvTerms j]

splits :: Int -> [(Int, Int)]
splits m = [(i, m - i) | i <- [1 .. m - 1]]

splits3 :: Int -> [[Int]]
splits3 m = [[i, j, m - i - j] | i <- [1 .. m - 2], j <- [1 .. m - i - 1]]

benchSizes :: [Int]
benchSizes = [10, 20, 40]

randomTerms :: Int -> [Term]
randomTerms n = unGen (vectorOf 100 (exact n)) (mkQCGen n) 30
  where
    exact :: Int -> Gen Term
    exact 1 = frequency [(3, elements [var "x", var "y"]), (2, elements (map bv [0, 1, 2, 255]))]
    exact 2 = exact 1 >>= un
    exact m = frequency [(1, exact (m - 1) >>= un), (4, chooseInt (1, m - 2) >>= \i -> do l <- exact i; r <- exact (m - 1 - i); bin l r)]
    un t = (\op -> Fix (UnF op t)) <$> elements [Not, Neg]
    bin l r = (\op -> Fix (BinF op l r)) <$> elements [Add, Sub, Mul, And, Or, Xor, Shl, Lshr]

sizeTable :: Orders -> IO ()
sizeTable o = do
  say ("result sizes on " <> showT (length benchSizes) <> " x 100 random BV terms (mean nodes; saturation: " <> showT limits <> ")")
  say ""
  say "| size | greedy, corpus order | greedy, reversed | saturation | no greedy normal form | saturation hit a limit |"
  say "|---|---|---|---|---|---|"
  mapM_ row benchSizes
  where
    row n = do
      let ts = randomTerms n
          gf = map (snd . normalise fuel (fwdFix o)) ts
          gr = map (snd . normalise fuel (revFix o)) ts
          sat = map (saturated (fwdChecked o)) ts
          stuck = length [() | nf <- gf ++ gr, not (isDone nf)]
          limited = length [() | (r, _) <- sat, satStop r /= Saturated]
      say ("| " <> showT n <> " | " <> mean (map nfSize gf) <> " | " <> mean (map nfSize gr) <> " | " <> mean (map (size . snd) sat) <> " | " <> showT stuck <> " | " <> showT limited <> " |")
    isDone (Done _) = True
    isDone _ = False

saturated :: [CheckedRule] -> Term -> (SatReport, Term)
saturated rs t = runST $ do
  g <- newEGraph
  i <- addTerm g t
  r <- saturate limits rs g
  e <- extract astSize g i
  pure (r, e)

nfSize :: NormalForm -> Int
nfSize (Done t) = size t
nfSize (Cycle _ ts) = lastSize ts
nfSize (OutOfFuel ts) = lastSize ts

lastSize :: [Term] -> Int
lastSize ts = case reverse ts of
  t : _ -> size t
  [] -> 0

showNF :: NormalForm -> Text
showNF (Done t) = pretty t <> " (" <> showT (size t) <> " nodes)"
showNF (Cycle k ts) = "cycle of length " <> showT k <> " after " <> showT (length ts) <> " steps"
showNF (OutOfFuel ts) = "out of fuel after " <> showT (length ts) <> " steps"

mean :: [Int] -> Text
mean xs = T.pack (printf "%.1f" (fromIntegral (sum xs) / fromIntegral (max 1 (length xs)) :: Double))

pretty :: Term -> Text
pretty = render . toExpr

toExpr :: Term -> Expr
toExpr (Fix l) = case l of
  VarF v -> Var v
  PVar v -> Var ("?" <> v)
  LitF v -> Lit v
  UnF op a -> Un op (toExpr a)
  BinF op a b -> Bin op (toExpr a) (toExpr b)
  CmpF op a b -> Cmp op (toExpr a) (toExpr b)
  IteF c a b -> Ite (toExpr c) (toExpr a) (toExpr b)

var :: Text -> Term
var = Fix . VarF

bv :: Integer -> Term
bv = Fix . LitF . VBV width

say :: Text -> IO ()
say = TIO.putStrLn

showT :: (Show a) => a -> Text
showT = T.pack . show
