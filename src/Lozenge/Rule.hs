module Lozenge.Rules (
  Rule (..),
  RuleWidth (..),
  instantiate,
)
where

import Data.Text (Text)
import Lozenge.Expr (Expr)
import Lozenge.Typecheck (Context)

data Rule = Rule
  { ruleName :: Text,
    ruleWidth :: RuleWidth,
    ruleVars :: Context,
    ruleLhs :: Expr,
    ruleRhs :: Expr,
    rulePre :: Maybe Expr
  }
  deriving (Eq, Show)

data RuleWidth
  = Fixed
  | Generic
  deriving (Eq, Show)

instantiate :: Int -> Rule -> Maybe Rule
instantiate = error "TODO: instantiate"
