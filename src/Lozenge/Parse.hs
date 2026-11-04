{-# LANGUAGE OverloadedStrings #-}

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

import Control.Monad (unless, void, when)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)
import Lozenge.Expr (Expr (..), Value (..), binOpName, cmpOpName, unOpName)
import Text.Megaparsec (
  ParseErrorBundle,
  Parsec,
  between,
  chunk,
  eof,
  getOffset,
  notFollowedBy,
  parse,
  region,
  satisfy,
  setErrorOffset,
  takeWhileP,
  try,
  (<?>),
  (<|>),
 )
import Text.Megaparsec.Char.Lexer qualified as L

type ParseError = ParseErrorBundle Text Void

parseExpr :: Text -> Either ParseError Expr
parseExpr = parse (whitespace *> exprWith (Var <$> identifier) constBody <* eof) ""

type Parser = Parsec Void Text

whitespace :: Parser ()
whitespace = void (takeWhileP Nothing (`elem` [' ', '\t', '\n']))

lexeme :: Parser a -> Parser a
lexeme p = p <* whitespace

isWordStart, isWordChar :: Char -> Bool
isWordStart c = isAsciiLower c || isAsciiUpper c || c == '_'
isWordChar c = isWordStart c || isDigit c

word :: Parser Text
word = T.cons <$> satisfy isWordStart <*> takeWhileP Nothing isWordChar

identifier :: Parser Text
identifier = lexeme (try reserved) <?> "identifier"
  where
    reserved = do
      name <- word
      when (name `elem` ["true", "false"]) (fail (T.unpack name <> " is reserved"))
      pure name

failAt :: Int -> String -> Parser a
failAt offset = region (setErrorOffset offset) . fail

natural :: String -> Parser Integer
natural label = lexeme L.decimal <?> label

constBody :: Parser Expr
constBody = do
  widthAt <- getOffset
  w <- natural "width"
  unless (1 <= w && w <= 64) (failAt widthAt ("width " <> show w <> " is not between 1 and 64"))
  valueAt <- getOffset
  v <- natural "value"
  unless (v < 2 ^ w) (failAt valueAt ("value " <> show v <> " does not fit in " <> show w <> " bits"))
  pure (Lit (VBV (fromInteger w) v))

exprWith :: Parser Expr -> Parser Expr -> Parser Expr
exprWith leaf constForm = expr
  where
    expr = (list <|> bool "true" True <|> bool "false" False <|> leaf) <?> "expression"
    bool name b = Lit (VBool b) <$ lexeme (try (chunk name <* notFollowedBy (satisfy isWordChar)))
    list = between (lexeme (chunk "(")) (lexeme (chunk ")")) form
    form = do
      headAt <- getOffset
      name <- lexeme (chunk "=" <|> word) <?> "operator"
      fromMaybe (failAt headAt ("unknown operator " <> T.unpack name)) (lookup name forms)
    forms =
      ("const", constForm)
        : ("ite", Ite <$> expr <*> expr <*> expr)
        : [(unOpName op, Un op <$> expr) | op <- [minBound .. maxBound]]
        ++ [(binOpName op, Bin op <$> expr <*> expr) | op <- [minBound .. maxBound]]
        ++ [(cmpOpName op, Cmp op <$> expr <*> expr) | op <- [minBound .. maxBound]]
