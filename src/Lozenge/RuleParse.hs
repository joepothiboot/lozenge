{-# LANGUAGE OverloadedStrings #-}

module Lozenge.RuleParse (
  parseRules,
  mkRule,
)
where

import Control.Monad (void, when)
import Data.Bifunctor (first)
import Data.Char (isAlphaNum, isAscii)
import Data.Foldable (for_)
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Lozenge.Expr (Expr (..), Value (..))
import Lozenge.Parse (ParseError, Parser, constBody, exprWith, failAt, identifier, lexeme, natural)
import Lozenge.Rule (Rule (..), RuleWidth (..), mapLiterals)
import Lozenge.Typecheck (Context, typecheck)
import Lozenge.Typed (SomeExpr, Ty (..), someSort)
import Text.Megaparsec (
  chunk,
  eof,
  getOffset,
  hidden,
  notFollowedBy,
  optional,
  parse,
  satisfy,
  skipMany,
  takeWhile1P,
  try,
  (<?>),
  (<|>),
 )
import Text.Megaparsec.Char.Lexer qualified as L

parseRules :: FilePath -> Text -> Either ParseError [Rule]
parseRules = parse (trivia *> rules Set.empty <* eof)

trivia :: Parser ()
trivia = lexeme (pure ()) <* skipMany (hidden (lexeme (L.skipLineComment ";")))

rules :: Set Text -> Parser [Rule]
rules seen = (rule seen >>= \r -> (r :) <$> rules (Set.insert (ruleName r) seen)) <|> pure []

rule :: Set Text -> Parser Rule
rule seen = do
  start <- getOffset

  symbol "("
  reserved "rule"

  name <- lexeme (takeWhile1P Nothing isNameChar) <?> "rule name"
  lhs <- term

  symbol "=>"

  rhs <- term
  pre <- optional (reserved ":if" *> term)

  symbol ")"

  r <- either (failAt start . T.unpack) pure (mkRule name lhs rhs pre)
  when (name `Set.member` seen) (failAt start ("duplicate rule name " <> T.unpack name))
  r <$ trivia

term :: Parser Expr
term = exprWith (Var <$> patternVar) (placeholder <|> constBody)
  where
    patternVar = chunk "?" *> identifier <?> "pattern variable"
    placeholder = Lit . VBV 0 <$> (reserved "w" *> natural "value")

symbol :: Text -> Parser ()
symbol = void . lexeme . chunk

reserved :: Text -> Parser ()
reserved word = void (lexeme (try (chunk word <* notFollowedBy (satisfy isNameChar)))) <?> show word

isNameChar :: Char -> Bool
isNameChar c = isAscii c && (isAlphaNum c || c == '_' || c == '-')

mkRule :: Text -> Expr -> Expr -> Maybe Expr -> Either Text Rule
mkRule name lhs0 rhs0 pre0 = first (("rule " <> name <> ": ") <>) $ do
  (kind, width) <- chooseWidth (literalWidths (lhs0 : rhs0 : foldMap pure pre0))

  let settle (VBV 0 v) = VBV width v
      settle v = v
      lhs = mapLiterals settle lhs0
      rhs = mapLiterals settle rhs0
      pre = mapLiterals settle <$> pre0
      bound = variables lhs

  checkBound "rhs" bound rhs

  for_ pre (checkBound "precondition" bound)

  vars <- inferSorts (TBV (fromIntegral width)) bound lhs rhs pre
  let typed part e = first (\err -> part <> " is ill-typed: " <> showT err) (typecheck vars e) :: Either Text SomeExpr
      sortName = showSort kind . someSort

  l <- typed "lhs" lhs
  r <- typed "rhs" rhs

  when (someSort l /= someSort r) (Left ("lhs has sort " <> sortName l <> " but rhs has sort " <> sortName r))

  for_ pre $ \p -> do
    t <- typed "precondition" p
    when (someSort t /= TBool) (Left ("precondition has sort " <> sortName t <> ", expected Bool"))
  pure (Rule name kind vars lhs rhs pre)

chooseWidth :: [Int] -> Either Text (RuleWidth, Int)
chooseWidth widths = case Set.toAscList (Set.fromList widths) of
  [] -> Right (Generic, 64)
  [0] -> Right (Generic, 64)
  [n]
    | n < 0 -> Left ("width " <> showT n <> " is not between 1 and 64")
    | otherwise -> Right (Fixed, n)
  0 : n : _ -> Left ("mixes the width placeholder w with width " <> showT n)
  a : b : _ -> Left ("uses widths " <> showT a <> " and " <> showT b <> "; a rule uses one width")

checkBound :: Text -> Set Text -> Expr -> Either Text ()
checkBound part bound e = for_ (Set.lookupMin (variables e `Set.difference` bound)) $ \x ->
  Left (part <> " uses ?" <> x <> ", which the lhs does not bind")

inferSorts :: Ty -> Set Text -> Expr -> Expr -> Maybe Expr -> Either Text Context
inferSorts bv bound lhs rhs pre = Map.traverseWithKey sortOf (Map.fromSet demandsOn bound)
  where
    demands = whole lhs ++ whole rhs ++ foldMap condition pre
    demandsOn x = nub [s | (y, s) <- demands, y == x]
    sortOf _ [s] = Right s
    sortOf x [] = Left ("cannot infer the sort of ?" <> x)
    sortOf x _ = Left ("?" <> x <> " is used as both Bool and BV")
    whole (Var _) = []
    whole (Lit _) = []
    whole (Un _ a) = operand a
    whole (Bin _ a b) = operand a ++ operand b
    whole (Cmp _ a b) = operand a ++ operand b
    whole (Ite c t e) = condition c ++ operand t ++ operand e
    operand (Var x) = [(x, bv)]
    operand e = whole e
    condition (Var x) = [(x, TBool)]
    condition e = whole e

subterms :: Expr -> [Expr]
subterms e =
  e : case e of
    Var _ -> []
    Lit _ -> []
    Un _ a -> subterms a
    Bin _ a b -> subterms a ++ subterms b
    Cmp _ a b -> subterms a ++ subterms b
    Ite c t f -> subterms c ++ subterms t ++ subterms f

literalWidths :: [Expr] -> [Int]
literalWidths es = [w | e <- es, Lit (VBV w _) <- subterms e]

variables :: Expr -> Set Text
variables e = Set.fromList [x | Var x <- subterms e]

showSort :: RuleWidth -> Ty -> Text
showSort _ TBool = "Bool"
showSort Generic (TBV _) = "BV w"
showSort Fixed (TBV n) = "BV " <> showT n

showT :: (Show a) => a -> Text
showT = T.pack . show
