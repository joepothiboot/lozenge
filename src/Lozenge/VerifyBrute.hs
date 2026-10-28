module Lozenge.VerifyBrute (
  Verdict (..),
  Assignment,
  assignmentCap,
  verifyBrute,
  renderVerdict,
)
where

import Data.Text (Text)
import Lozenge.Expr (Env, Value)
import Lozenge.Rule (Rule)

type Assignment = Env

data Verdict
  = Valid
  | Counterexample Assignment Value Value
  | Unsupported Text
  deriving (Eq, Show)

assignmentCap :: Integer
assignmentCap = 2 ^ (20 :: Int)

verifyBrute :: Int -> Rule -> Verdict
verifyBrute = error "TODO: verifyBrute"

renderVerdict :: Verdict -> Text
renderVerdict = error "TODO: renderVerdict"
