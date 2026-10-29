module Lozenge.Saturate (
  CheckedRule,
  checkedRule,
  loadRules,
  Limits (..),
  StopReason (..),
  SatReport (..),
  saturate,
)
where

import Control.Monad.ST (ST)
import Data.Text (Text)
import Lozenge.EGraph (EGraph)
import Lozenge.Rule (Rule)

data CheckedRule

checkedRule :: CheckedRule -> Rule
checkedRule = error "TODO: checkedRule"

loadRules :: Int -> [Rule] -> ([CheckedRule], [(Text, Text)])
loadRules = error "TODO: loadRules"

data Limits = Limits
  { limIters :: Int,
    limNodes :: Int,
    limMatches :: Int,
    limBan :: Int
  }
  deriving (Eq, Show)

data StopReason
  = Saturated
  | IterLimit
  | NodeLimit
  deriving (Eq, Show)

data SatReport = SatReport
  { satStop :: StopReason,
    satIterations :: Int,
    satNodes :: Int,
    satBanned :: [Text]
  }
  deriving (Eq, Show)

saturate :: Limits -> [CheckedRule] -> EGraph s -> ST s SatReport
saturate = error "TODO: saturate"
