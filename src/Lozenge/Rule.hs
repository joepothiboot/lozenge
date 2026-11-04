module Lozenge.Rule (
  Rule (..),
  RuleWidth (..),
  instantiate,
  mapLiterals,
)
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Lozenge.Expr (Expr (..), Value (..))
import Lozenge.Typecheck (Context)
import Lozenge.Typed (Ty (..))

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
instantiate _ r@Rule{ruleWidth = Fixed} = Just r
instantiate w r
  | w < 1 || w > 64 = Nothing
  | otherwise =
      Just
        r
          { ruleVars = Map.map resize (ruleVars r),
            ruleLhs = literals (ruleLhs r),
            ruleRhs = literals (ruleRhs r),
            rulePre = literals <$> rulePre r
          }
  where
    resize TBool = TBool
    resize (TBV _) = TBV (fromIntegral w)
    literals = mapLiterals lowBits
    lowBits (VBV _ v) = VBV w (v `mod` 2 ^ w)
    lowBits b = b

mapLiterals :: (Value -> Value) -> Expr -> Expr
mapLiterals _ (Var x) = Var x
mapLiterals f (Lit v) = Lit (f v)
mapLiterals f (Un op a) = Un op (mapLiterals f a)
mapLiterals f (Bin op a b) = Bin op (mapLiterals f a) (mapLiterals f b)
mapLiterals f (Cmp op a b) = Cmp op (mapLiterals f a) (mapLiterals f b)
mapLiterals f (Ite c t e) = Ite (mapLiterals f c) (mapLiterals f t) (mapLiterals f e)
