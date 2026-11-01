{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Cli (
  Command (..),
  Solver (..),
  Cost (..),
  Engine (..),
  run,
)
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (when)
import Control.Monad.Except (ExceptT (..), liftEither, runExceptT, throwError, withExceptT)
import Control.Monad.ST (runST)
import Data.Aeson (ToJSON)
import Data.Aeson.Text (encodeToLazyText)
import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import Lozenge.Critical (CriticalPair (..), Joinability (..), PairVerdict (..), checkPair, criticalPairs, renderPair)
import Lozenge.EGraph (addTerm, newEGraph)
import Lozenge.Expr (Expr (..), Value (..))
import Lozenge.ExprF (ExprF (..), ruleToFix, toTyped, vars)
import Lozenge.Extract (astSize, extract, shiftsAreCheap)
import Lozenge.Fix (Fix, ana, cata)
import Lozenge.Json qualified as J
import Lozenge.Parse (parseExpr)
import Lozenge.Pretty (render)
import Lozenge.Rewrite (NormalForm (..), normalise)
import Lozenge.Rule (Rule (..), instantiate)
import Lozenge.RuleParse (parseRules)
import Lozenge.Saturate (Limits (..), SatReport (..), StopReason (..), checkedRule, loadRules, saturate)
import Lozenge.Typed (Ty (..))
import Lozenge.VerifyBrute (Verdict (..), renderVerdict, verifyBrute)
import Lozenge.VerifySmt (Config (..), Verify, VerifyError (..), runVerify, verifySmt)
import System.Exit (ExitCode (..))
import Text.Megaparsec (errorBundlePretty)

data Solver = Brute | Smt | Both
  deriving (Eq, Show)

data Cost = Size | Shifts
  deriving (Eq, Show)

data Engine = Greedy | EGraph
  deriving (Eq, Show)

data Command
  = Verify FilePath Int Solver
  | Optimize FilePath FilePath Int Cost Engine
  | CriticalPairs FilePath Int
  deriving (Eq, Show)

type Cli = ExceptT Text IO

run :: Bool -> Command -> IO (Either Text (ExitCode, Text))
run json =
  runExceptT . \case
    Verify path w solver -> verify json path w solver
    Optimize expr rules w cost engine -> optimize json expr rules w cost engine
    CriticalPairs path w -> pairs json path w

verify :: Bool -> FilePath -> Int -> Solver -> Cli (ExitCode, Text)
verify json path w solver = do
  rules <- readRules path
  smt <-
    if solver == Brute
      then pure (Nothing <$ rules)
      else map Just <$> smtRun w (traverse verifySmt rules)
  let brute = [if solver == Smt then Nothing else Just (verifyBrute w r) | r <- rules]
      results = zip3 (map ruleName rules) brute smt
      statuses = [status (catMaybes [b, s]) | (_, b, s) <- results]
      count k = length (filter (== k) statuses)
      summary = T.intercalate ", " [showT (count k) <> " " <> k | k <- ["valid", "invalid", "unsupported"]] <> " at width " <> showT w
      code = if count "invalid" > 0 then ExitFailure 1 else ExitSuccess
      report = J.VerifyReport w [J.RuleReport n (verdictJ <$> b) (verdictJ <$> s) | (n, b, s) <- results]
      line (n, b, s) = [n <> " [" <> tag <> "]: " <> renderVerdict v | (tag, Just v) <- [("brute", b), ("smt", s)]]
  pure (code, if json then encode report else T.unlines (concatMap line results ++ [summary]))
  where
    status vs
      | any isCounterexample vs = "invalid"
      | any isUnsupported vs = "unsupported"
      | otherwise = "valid" :: Text

optimize :: Bool -> FilePath -> FilePath -> Int -> Cost -> Engine -> Cli (ExitCode, Text)
optimize json exprPath rulesPath w cost engine = do
  rules <- readRules rulesPath
  src <- readText exprPath
  t <- either (throwError . (T.pack exprPath <>) . (": " <>) . T.pack . errorBundlePretty) (pure . fromExpr) (parseExpr src)
  let ctx = Map.fromSet (const (TBV (fromIntegral w))) (vars t)
  _ <- liftEither (first (\e -> T.pack exprPath <> ": ill-typed at width " <> showT w <> ": " <> showT e) (toTyped ctx t))
  when (cata (\case LitF (VBV n _) -> n /= w; layer -> or layer) t) $
    throwError (T.pack exprPath <> ": every constant must have width " <> showT w <> ", the width the rules are loaded at")
  let (checked, refused) = loadRules w rules
  (out, stop, skipped) <- case engine of
    Greedy -> do
      fixes <- liftEither (traverse (ruleToFix . checkedRule) checked)
      let (names, nf) = normalise fuel fixes t
      pure (case nf of Done u -> (u, "done", names); Cycle _ us -> (lastOr t us, "cycle", names); OutOfFuel us -> (lastOr t us, "out-of-fuel", names))
    EGraph -> pure (runST (saturated checked t))
  let report =
        J.OptimizeReport
          { J.orWidth = w,
            J.orInput = renderTerm t,
            J.orOutput = renderTerm out,
            J.orInputCost = cata costFn t,
            J.orOutputCost = cata costFn out,
            J.orStop = stop,
            J.orRefused = [J.Refused n why | (n, why) <- refused] ++ [J.Refused n "has a precondition, which greedy rewriting skips" | n <- skipped]
          }
      text =
        T.unlines $
          [J.orOutput report, "cost " <> showT (J.orInputCost report) <> " -> " <> showT (J.orOutputCost report) <> " (" <> stop <> ")"]
            ++ ["not used at width " <> showT w <> ": " <> T.intercalate ", " (map J.rfRule (J.orRefused report)) | not (null (J.orRefused report))]
  pure (ExitSuccess, if json then encode report else text)
  where
    costFn = case cost of
      Size -> astSize
      Shifts -> shiftsAreCheap
    saturated checked t = do
      g <- newEGraph
      i <- addTerm g t
      r <- saturate limits checked g
      e <- extract costFn g i
      pure (e, stopName (satStop r), [])
    stopName = \case
      Saturated -> "saturated"
      IterLimit -> "iter-limit"
      NodeLimit -> "node-limit"

pairs :: Bool -> FilePath -> Int -> Cli (ExitCode, Text)
pairs json path w = do
  rules <- readRules path
  sized <- maybe (throwError ("cannot instantiate the rules at width " <> showT w)) pure (traverse (instantiate w) rules)
  fixes <- liftEither (traverse ruleToFix sized)
  let cps = criticalPairs fixes
  vs <- smtRun w (traverse (checkPair fuel fixes) cps)
  let kinds = map kind vs
      count k = length (filter (== k) kinds)
      summary = showT (length cps) <> " critical pairs at width " <> showT w <> ": " <> T.intercalate ", " [showT (count k) <> " " <> k | k <- ["joinable", "semantically equal", "unsound", "unchecked"]]
      report = J.PairsReport w (zipWith pairJ cps vs)
  pure (ExitSuccess, if json then encode report else T.intercalate "\n" (zipWith renderPair cps vs ++ [summary <> "\n"]))
  where
    kind = \case
      Joinable _ -> "joinable"
      NotJoinable _ Valid -> "semantically equal"
      NotJoinable _ Counterexample{} -> "unsound"
      NotJoinable _ (Unsupported _) -> "unchecked" :: Text
    pairJ cp v =
      J.Pair
        { J.pOuter = cpOuter cp,
          J.pInner = cpInner cp,
          J.pPosition = cpPos cp,
          J.pPeak = renderTerm (cpPeak cp),
          J.pLeft = renderTerm (cpLeft cp),
          J.pRight = renderTerm (cpRight cp),
          J.pJoin = case v of
            Joinable u -> J.Joined (renderTerm u)
            NotJoinable j _ -> joinJ j,
          J.pCheck = case v of
            Joinable _ -> Nothing
            NotJoinable _ c -> Just (verdictJ c)
        }
    joinJ = \case
      Joined u -> J.Joined (renderTerm u)
      NotJoined a b -> J.NotJoined (renderTerm a) (renderTerm b)
      Unknown -> J.Unknown

fuel :: Int
fuel = 100

limits :: Limits
limits = Limits{limIters = 10, limNodes = 10000, limMatches = 1000, limBan = 2}

timeoutMs :: Int
timeoutMs = 10000

smtRun :: Int -> Verify a -> Cli a
smtRun w = withExceptT why . ExceptT . runVerify (Config w timeoutMs)
  where
    why = \case
      SolverFailed msg -> "smt: " <> msg
      SpuriousCounterexample a -> "smt: z3 gave a counterexample that is not one: " <> showT a

readText :: FilePath -> Cli Text
readText path = ExceptT (first (T.pack . displayException) <$> try @IOException (TIO.readFile path))

readRules :: FilePath -> Cli [Rule]
readRules path = readText path >>= liftEither . first (T.pack . errorBundlePretty) . parseRules path

verdictJ :: Verdict -> J.Verdict
verdictJ = \case
  Valid -> J.Valid
  Counterexample env l r -> J.Invalid (valueJ <$> env) (valueJ l) (valueJ r)
  Unsupported why -> J.Unsupported why
  where
    valueJ (VBV n v) = J.VBV n v
    valueJ (VBool b) = J.VBool b

isCounterexample, isUnsupported :: Verdict -> Bool
isCounterexample = \case Counterexample{} -> True; _ -> False
isUnsupported = \case Unsupported _ -> True; _ -> False

fromExpr :: Expr -> Fix ExprF
fromExpr = ana $ \case
  Var v -> VarF v
  Lit v -> LitF v
  Un op a -> UnF op a
  Bin op a b -> BinF op a b
  Cmp op a b -> CmpF op a b
  Ite c a b -> IteF c a b

renderTerm :: Fix ExprF -> Text
renderTerm = render . cata toExpr
  where
    toExpr = \case
      VarF v -> Var v
      PVar v -> Var ("?" <> v)
      LitF v -> Lit v
      UnF op a -> Un op a
      BinF op a b -> Bin op a b
      CmpF op a b -> Cmp op a b
      IteF c a b -> Ite c a b

lastOr :: a -> [a] -> a
lastOr x xs = NE.last (x :| xs)

encode :: (ToJSON a) => a -> Text
encode = (<> "\n") . TL.toStrict . encodeToLazyText

showT :: (Show a) => a -> Text
showT = T.pack . show
