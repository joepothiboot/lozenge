module Lozenge.Smt (
  smtName,
  toSmt,
  ruleQuery,
)
where

import Data.Text (Text)
import Lozenge.Rule (Rule)
import Lozenge.Typed (TExpr)

smtName :: Text -> Text
smtName = error "TODO: smtName"

toSmt :: TExpr t -> Text
toSmt = error "TODO: toSmt"

ruleQuery :: Rule -> Either Text Text
ruleQuery = error "TODO: ruleQuery"
