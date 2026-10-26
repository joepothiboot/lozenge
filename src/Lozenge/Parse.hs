module Lozenge.Parse
  ( ParseError,
    parseExpr,
  )
where

import Data.Text (Text)
import Data.Void (Void)
import Lozenge.Expr (Expr)
import Text.Megaparsec (ParseErrorBundle)

type ParseError = ParseErrorBundle Text Void

parseExpr :: Text -> Either ParseError Expr
parseExpr = error "TODO: parseExpr"
