{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Smt (
  smtName,
  toSmt,
  ruleQuery,
)
where

import Control.Monad (when)
import Data.Bifunctor (first)
import Data.Foldable (toList, traverse_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Lozenge.Expr (BinOp (..), CmpOp (..), UnOp (..))
import Lozenge.Rule (Rule (..))
import Lozenge.Typecheck (checkTy, typecheck)
import Lozenge.Typed (SomeExpr (..), TExpr (..), Ty (..), Value (..), someSort, widthOf)

smtName :: Text -> Text
smtName = ("v_" <>)

toSmt :: TExpr t -> Text
toSmt (TVar _ x) = smtName x
toSmt (TLit (VBool True)) = "true"
toSmt (TLit (VBool False)) = "false"
toSmt (TLit (VBV w v)) = form ["_", "bv" <> showT v, showT (widthOf w)]
toSmt (TUn op a) = form [unOp op, toSmt a]
toSmt (TBin op a b) = form [binOp op, toSmt a, toSmt b]
toSmt (TCmp op a b) = form [cmpOp op, toSmt a, toSmt b]
toSmt (TIte c t e) = form ["ite", toSmt c, toSmt t, toSmt e]

unOp :: UnOp -> Text
unOp Not = "bvnot"
unOp Neg = "bvneg"

binOp :: BinOp -> Text
binOp Add = "bvadd"
binOp Sub = "bvsub"
binOp Mul = "bvmul"
binOp And = "bvand"
binOp Or = "bvor"
binOp Xor = "bvxor"
binOp Shl = "bvshl"
binOp Lshr = "bvlshr"

cmpOp :: CmpOp -> Text
cmpOp Eq = "="
cmpOp Ult = "bvult"
cmpOp Slt = "bvslt"

ruleQuery :: Rule -> Either Text Text
ruleQuery r = do
  let vars = ruleVars r
      check = first showT . typecheck vars
  traverse_ (first showT . checkTy) vars

  lhs <- check (ruleLhs r)
  rhs <- check (ruleRhs r)

  when (someSort lhs /= someSort rhs) (Left "lhs and rhs have different sorts")

  pre <- traverse check (rulePre r)

  when (any ((/= TBool) . someSort) pre) (Left "the precondition is not Bool")

  pure . T.unlines $
    ["(set-option :produce-models true)", "(set-logic QF_BV)"]
      <> [form ["declare-const", smtName x, smtSort ty] | (x, ty) <- Map.toAscList vars]
      <> [form ["assert", term p] | p <- toList pre]
      <> [form ["assert", form ["not", form ["=", term lhs, term rhs]]]]
      <> ["(check-sat)"]
      <> [form ["get-value", form (smtName <$> Map.keys vars)] | not (Map.null vars)]

term :: SomeExpr -> Text
term (SomeExpr _ t) = toSmt t

smtSort :: Ty -> Text
smtSort TBool = "Bool"
smtSort (TBV w) = form ["_", "BitVec", showT w]

form :: [Text] -> Text
form parts = "(" <> T.unwords parts <> ")"

showT :: (Show a) => a -> Text
showT = T.pack . show
