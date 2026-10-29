module Lozenge.Critical (
  rename,
  CriticalPair (..),
  criticalPairs,
  Joinability (..),
  joinable,
  PairVerdict (..),
  checkPair,
  renderPair,
)
where

import Control.Monad.State (State)
import Data.Text (Text)
import Lozenge.ExprF (ExprF, FixRule)
import Lozenge.Fix (Fix)
import Lozenge.Typecheck (Context)
import Lozenge.VerifyBrute (Verdict)
import Lozenge.VerifySmt (Verify)

rename :: FixRule -> State Int FixRule
rename = error "TODO: rename"

data CriticalPair = CriticalPair
  { cpOuter :: Text,
    cpInner :: Text,
    cpPos :: [Int],
    cpPeak :: Fix ExprF,
    cpLeft :: Fix ExprF,
    cpRight :: Fix ExprF,
    cpVars :: Context
  }
  deriving (Eq, Show)

criticalPairs :: [FixRule] -> [CriticalPair]
criticalPairs = error "TODO: criticalPairs"

data Joinability
  = Joined (Fix ExprF)
  | NotJoined (Fix ExprF) (Fix ExprF)
  | Unknown
  deriving (Eq, Show)

joinable :: Int -> [FixRule] -> CriticalPair -> Joinability
joinable = error "TODO: joinable"

data PairVerdict
  = Joinable (Fix ExprF)
  | NotJoinable Joinability Verdict
  deriving (Eq, Show)

checkPair :: Int -> [FixRule] -> CriticalPair -> Verify PairVerdict
checkPair = error "TODO: checkPair"

renderPair :: CriticalPair -> PairVerdict -> Text
renderPair = error "TODO: renderPair"
