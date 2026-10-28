module Lozenge.Parse (
  ParseError,
  parseExpr,
  Parser,
  lexeme,
  identifier,
  constBody,
  exprWith,
)
where

import Data.Text (Text)
import Data.Void (Void)
import Lozenge.Expr (Expr)
import Text.Megaparsec (ParseErrorBundle, Parsec)

type ParseError = ParseErrorBundle Text Void

parseExpr :: Text -> Either ParseError Expr
parseExpr = error "TODO: parseExpr"

type Parser = Parsec Void Text

lexeme :: Parser a -> Parser a
lexeme = error "TODO: lexeme"

identifier :: Parser Text
identifier = error "TODO: identifier"

constBody :: Parser Expr
constBody = error "TODO: constBody"

exprWith :: Parser Expr -> Parser Expr -> Parser Expr
exprWith = error "TODO: exprWith"
