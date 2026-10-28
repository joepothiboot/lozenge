module Lozenge.RuleParse (
  parseRules,
  mkRule,
)
where

import Data.Text (Text)
import Lozenge.Expr (Expr)
import Lozenge.Parse (ParseError)
import Lozenge.Rule (Rule)

parseRules :: FilePath -> Text -> Either ParseError [Rule]
parseRules = error "TODO: parseRules"

mkRule :: Text -> Expr -> Expr -> Maybe Expr -> Either Text Rule
mkRule = error "TODO: mkRule"
