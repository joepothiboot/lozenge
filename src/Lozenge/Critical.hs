{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Critical (
  rename,
  CriticalPair (..),
  criticalPairs,
  Joinability (..),
  joinable,
  PairVerdict (..),
  checkPair,
  renderPair,
)
where

import Control.Monad.State (State, evalState, state)
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Traversable (mapAccumL)
import Lozenge.Expr (Value (..), binOpName, cmpOpName, unOpName)
import Lozenge.ExprF (ExprF (..), FixRule (..), toTyped, vars)
import Lozenge.Fix (Fix (..), cata, para)
import Lozenge.Rewrite (NormalForm (..), applySubst, normalise, unify)
import Lozenge.Rule (Rule (..), RuleWidth (..))
import Lozenge.Typecheck (Context)
import Lozenge.Typed (SomeExpr (..), erase)
import Lozenge.VerifyBrute (Verdict (..), renderVerdict)
import Lozenge.VerifySmt (Verify, verifySmt)

rename :: FixRule -> State Int FixRule
rename r = do
  fresh <- Map.fromList <$> traverse next (Set.toAscList names)
  let side = applySubst (Fix . PVar <$> fresh)
  pure
    r
      { frVars = Map.fromList (Map.elems (Map.intersectionWith (,) fresh (frVars r))),
        frLhs = side (frLhs r),
        frRhs = side (frRhs r),
        frPre = side <$> frPre r
      }
  where
    names = Set.unions (Map.keysSet (frVars r) : map vars (frLhs r : frRhs r : toList (frPre r)))
    next x = state (\n -> ((x, x <> "_" <> showT n), n + 1))

data CriticalPair = CriticalPair
  { cpOuter :: Text,
    cpInner :: Text,
    cpPos :: [Int],
    cpPeak :: Fix ExprF,
    cpLeft :: Fix ExprF,
    cpRight :: Fix ExprF,
    cpVars :: Context
  }
  deriving (Eq, Show)

criticalPairs :: [FixRule] -> [CriticalPair]
criticalPairs rules =
  [ CriticalPair
      { cpOuter = frName outer,
        cpInner = frName inner,
        cpPos = p,
        cpPeak = peak,
        cpLeft = applySubst s (frRhs outer),
        cpRight = replaceAt p (applySubst s (frRhs inner)) peak,
        cpVars = Map.union (frVars outer) (frVars inner)
      }
  | (o, outer, _) <- copies,
    (p, sub) <- positions (frLhs outer),
    (i, _, inner) <- copies,
    not (o == i && null p),
    Just s <- [unify sub (frLhs inner)],
    let peak = applySubst s (frLhs outer)
  ]
  where
    copies = zip3 [0 :: Int ..] renamedOuter renamedInner
    (renamedOuter, renamedInner) = evalState ((,) <$> traverse rename active <*> traverse rename active) 0
    active = filter (isNothing . frPre) rules

positions :: Fix ExprF -> [([Int], Fix ExprF)]
positions = para alg
  where
    alg (PVar _) = []
    alg l = ([], Fix (fst <$> l)) : [(i : p, t) | (i, (_, below)) <- zip [0 ..] (toList l), (p, t) <- below]

replaceAt :: [Int] -> Fix ExprF -> Fix ExprF -> Fix ExprF
replaceAt [] new _ = new
replaceAt (i : is) new (Fix l) = Fix (snd (mapAccumL step 0 l))
  where
    step n c = (n + 1, if n == i then replaceAt is new c else c)

data Joinability
  = Joined (Fix ExprF)
  | NotJoined (Fix ExprF) (Fix ExprF)
  | Unknown
  deriving (Eq, Show)

joinable :: Int -> [FixRule] -> CriticalPair -> Joinability
joinable fuel rules cp = case (normal (cpLeft cp), normal (cpRight cp)) of
  (Done l, Done r)
    | l == r -> Joined l
    | otherwise -> NotJoined l r
  _ -> Unknown
  where
    normal = snd . normalise fuel rules

data PairVerdict
  = Joinable (Fix ExprF)
  | NotJoinable Joinability Verdict
  deriving (Eq, Show)

checkPair :: Int -> [FixRule] -> CriticalPair -> Verify PairVerdict
checkPair fuel rules cp = case joinable fuel rules cp of
  Joined t -> pure (Joinable t)
  j -> NotJoinable j <$> either (pure . Unsupported . showT) verifySmt reducts
  where
    reducts = reductRule <$> back (cpLeft cp) <*> back (cpRight cp)
    back t = (\(SomeExpr _ e) -> erase e) <$> toTyped (cpVars cp) t
    reductRule l r =
      Rule
        { ruleName = cpOuter cp <> "/" <> cpInner cp,
          ruleWidth = Fixed,
          ruleVars = cpVars cp,
          ruleLhs = l,
          ruleRhs = r,
          rulePre = Nothing
        }

renderPair :: CriticalPair -> PairVerdict -> Text
renderPair cp verdict =
  T.unlines
    [ cpOuter cp <> " / " <> cpInner cp <> " at " <> showT (cpPos cp),
      "  peak:  " <> term (cpPeak cp),
      "  left:  " <> term (cpLeft cp),
      "  right: " <> term (cpRight cp),
      "  " <> line verdict
    ]
  where
    line (Joinable t) = "joinable: " <> term t
    line (NotJoinable (Joined t) v) = "joinable: " <> term t <> "; " <> check v
    line (NotJoinable (NotJoined l r) v) = "not joined: normal forms " <> term l <> " and " <> term r <> "; " <> check v
    line (NotJoinable Unknown v) = "not joined: no normal form within the budget; " <> check v
    check Valid = "syntactically different, semantically equal"
    check v@Counterexample{} = "UNSOUND: " <> renderVerdict v
    check (Unsupported msg) = "not checked: " <> msg

term :: Fix ExprF -> Text
term = cata alg
  where
    alg (VarF x) = x
    alg (PVar x) = "?" <> x
    alg (LitF (VBool True)) = "true"
    alg (LitF (VBool False)) = "false"
    alg (LitF (VBV w v)) = form ["const", showT w, showT v]
    alg (UnF op a) = form [unOpName op, a]
    alg (BinF op a b) = form [binOpName op, a, b]
    alg (CmpF op a b) = form [cmpOpName op, a, b]
    alg (IteF c t e) = form ["ite", c, t, e]
    form parts = "(" <> T.unwords parts <> ")"

showT :: (Show a) => a -> Text
showT = T.pack . show
