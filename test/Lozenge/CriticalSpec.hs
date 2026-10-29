{-# LANGUAGE OverloadedStrings #-}

module Lozenge.CriticalSpec (tests) where

import Control.Monad.State (State, evalState, get, put, runState)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Traversable (mapAccumL)
import Golden (goldenText)
import Lozenge.Critical
import Lozenge.Expr (BinOp (..), CmpOp (..), UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.ExprF (ExprF (..), FixRule (..))
import Lozenge.Fix (Fix (..))
import Lozenge.Rewrite (applySubst, match)
import Lozenge.Rule (RuleWidth (..))
import Lozenge.Typed (Ty (..))
import Lozenge.VerifyBrute (Verdict (..))
import Lozenge.VerifySmt (Config (..), runVerify)
import Props (props)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, checkCoverage, conjoin, counterexample, cover, elements, forAll, frequency, testProperty)
import Z3 (requireZ3)

tests :: TestTree
tests =
  testGroup
    "Critical"
    [ testGroup
        "rename"
        [ testCase "one variable, from 0" $
            runState (rename addZero) 0
              @?= ( (rule "add-zero" (add (pv "x_0") zero) (pv "x_0")){frVars = Map.fromList [("x_0", TBV 8)]},
                    1
                  ),
          testCase "names in ascending order, from 5" $
            runState (rename comm) 5
              @?= ((rule "comm" (add (pv "x_5") (pv "y_6")) (add (pv "y_6") (pv "x_5"))){frVars = Map.fromList [("x_5", TBV 8), ("y_6", TBV 8)]}, 7),
          testCase "the precondition too" $
            frPre (evalState (rename guarded) 0) @?= Just (Fix (CmpF Ult (pv "x_0") zero)),
          testCase "two renames from one counter share no variable" $ do
            let (r1, r2) = evalState ((,) <$> rename comm <*> rename comm) 0
            Set.disjoint (Map.keysSet (frVars r1)) (Map.keysSet (frVars r2)) @?= True
        ],
      testGroup
        "criticalPairs, by hand"
        [ testCase "f(g(x)) -> a and g(b) -> c" $ canonAll setA @?= sort pairsA,
          testCase "add-zero and comm" $ canonAll setB @?= sort pairsB,
          testCase "not-not and de-morgan-and" $ canonAll setC @?= sort pairsC,
          testCase "a rule with a precondition is skipped" $ canonAll [guarded, addZero] @?= [],
          testCase "a rule alone: no root self-overlap" $ canonAll [addZero] @?= [],
          testCase "the same rule twice in the list overlaps at the root" $
            map (\(o, i, p, _, _, _) -> (o, i, p)) (canonAll [comm, comm]) @?= [("comm", "comm", []), ("comm", "comm", [])],
          testCase "the variables and their sorts" $ case criticalPairs setC of
            [_, cp] -> Map.elems (cpVars cp) @?= replicate 3 (TBV 8)
            cps -> assertFailure ("expected two pairs, got " <> show cps),
          props $
            testProperty "each peak rewrites to exactly its two reducts" $
              forAll genRules $ \rs ->
                let cps = criticalPairs rs
                 in checkCoverage . cover 40 (not (null cps)) "has pairs" $ conjoin (map (peakLaw rs) cps)
        ],
      testGroup
        "joinable"
        [ testCase "f(g(x)) -> a and g(b) -> c: two normal forms" $
            map (joinable 10 setA) (criticalPairs setA) @?= [NotJoined a (notE c)],
          testCase "add-zero then comm: both pairs join" $
            map (isJoined . joinable 10 setB) (criticalPairs setB) @?= [True, True],
          testCase "comm then add-zero: comm cycles first, so Unknown" $
            map (joinable 10 [comm, addZero]) (criticalPairs [comm, addZero]) @?= [Unknown, Unknown],
          testCase "not-not and de-morgan-and" $
            map (canonJ . joinable 10 setC) (criticalPairs setC)
              @?= [Joined (notE (pv "v0")), NotJoined (andE (pv "v0") (pv "v1")) (notE (orE (notE (pv "v0")) (notE (pv "v1"))))]
        ],
      testGroup
        "checkPair"
        [ testCase "a joined pair needs no z3" $ do
            v <- check setC =<< pairAt setC 0
            fmap canonV v @?= Right (Joinable (notE (pv "v0"))),
          testCase "a VarF constant is not in cpVars: Unsupported before z3" $ do
            v <- check setA =<< pairAt setA 0
            case v of
              Right (NotJoinable (NotJoined _ _) (Unsupported _)) -> pure ()
              other -> assertFailure ("expected NotJoinable _ (Unsupported _), got " <> show other),
          requireZ3 "de Morgan: syntactically different, semantically equal" $ do
            v <- check setC =<< pairAt setC 1
            case v of
              Right (NotJoinable (NotJoined _ _) Valid) -> pure ""
              other -> assertFailure ("expected NotJoinable _ Valid, got " <> show other),
          requireZ3 "xor-self and the wrong xor-left: unsound" $ do
            vs <- traverse (check bogus) (criticalPairs bogus)
            length vs @?= 2
            mapM_ unsound vs
            pure ""
        ],
      goldenText "renderPair" "critical-pairs.txt" (pure (T.intercalate "\n" (map (uncurry renderPair) rendered)))
    ]

setA :: [FixRule]
setA = [fg, gb]

pairsA :: [Canon]
pairsA = [("f-g", "g-b", [0], notE (neg b), a, notE c)]


setB :: [FixRule]
setB = [addZero, comm]

pairsB :: [Canon]
pairsB =
  [ ("add-zero", "comm", [], add (pv "v0") zero, pv "v0", add zero (pv "v0")),
    ("comm", "add-zero", [], add (pv "v0") zero, add zero (pv "v0"), pv "v0")
  ]


setC :: [FixRule]
setC = [notNot, deMorgan]

pairsC :: [Canon]
pairsC =
  [ ("not-not", "not-not", [0], notE (notE (notE (pv "v0"))), notE (pv "v0"), notE (pv "v0")),
    ( "not-not",
      "de-morgan-and",
      [0],
      notE (notE (andE (pv "v0") (pv "v1"))),
      andE (pv "v0") (pv "v1"),
      notE (orE (notE (pv "v0")) (notE (pv "v1")))
    )
  ]


bogus :: [FixRule]
bogus = [xorSelf, xorLeft]

rendered :: [(CriticalPair, PairVerdict)]
rendered =
  [ ( CriticalPair "f-g" "g-b" [0] (notE (neg b)) a (notE c) (vars8 ["x_0"]),
      NotJoinable (NotJoined a (notE c)) (Unsupported "a is not in cpVars")
    ),
    ( CriticalPair "not-not" "not-not" [0] (notE (notE (notE (pv "x_1")))) (notE (pv "x_1")) (notE (pv "x_1")) (vars8 ["x_0", "x_1"]),
      Joinable (notE (pv "x_1"))
    ),
    ( CriticalPair "not-not" "de-morgan-and" [0] (notE (notE (andE x1 y2))) (andE x1 y2) deMorgan12 (vars8 ["x_0", "x_1", "y_2"]),
      NotJoinable (NotJoined (andE x1 y2) deMorgan12) Valid
    ),
    ( CriticalPair "xor-self" "xor-left" [] (xor (pv "x_0") (pv "x_0")) zero (pv "x_0") (vars8 ["x_0", "x_1", "y_2"]),
      NotJoinable
        (NotJoined zero (pv "x_0"))
        (Counterexample (Map.fromList [("x_0", U.VBV 8 1)]) (U.VBV 8 0) (U.VBV 8 1))
    ),
    ( CriticalPair "comm" "add-zero" [] (add (pv "x_0") zero) (add zero (pv "x_0")) (pv "x_0") (vars8 ["x_0", "y_1", "x_2"]),
      NotJoinable Unknown Valid
    )
  ]
  where
    x1 = pv "x_1"
    y2 = pv "y_2"
    deMorgan12 = notE (orE (notE x1) (notE y2))

pairAt :: [FixRule] -> Int -> IO CriticalPair
pairAt rs k = case drop k (criticalPairs rs) of
  cp : _ -> pure cp
  [] -> assertFailure ("fewer than " <> show (k + 1) <> " critical pairs")

check :: [FixRule] -> CriticalPair -> IO (Either String PairVerdict)
check rs cp = either (Left . show) Right <$> runVerify (Config 8 10000) (checkPair 10 rs cp)

unsound :: Either String PairVerdict -> IO ()
unsound (Right (NotJoinable (NotJoined _ _) Counterexample{})) = pure ()
unsound other = assertFailure ("expected NotJoinable _ (Counterexample ..), got " <> show other)

isJoined :: Joinability -> Bool
isJoined (Joined _) = True
isJoined _ = False


peakLaw :: [FixRule] -> CriticalPair -> Bool
peakLaw rs cp = case (byName (cpOuter cp), byName (cpInner cp)) of
  (Just o, Just i) ->
    rewriteAt o [] (cpPeak cp) == Just (cpLeft cp)
      && rewriteAt i (cpPos cp) (cpPeak cp) == Just (cpRight cp)
      && all (all (`Map.member` cpVars cp) . pvars) [cpPeak cp, cpLeft cp, cpRight cp]
  _ -> False
  where
    byName n = lookup n [(frName r, r) | r <- rs]

rewriteAt :: FixRule -> [Int] -> Fix ExprF -> Maybe (Fix ExprF)
rewriteAt r [] t = (`applySubst` frRhs r) <$> match (frLhs r) t
rewriteAt r (i : is) (Fix l)
  | i < length l = Fix <$> sequenceA (snd (mapAccumL step 0 l))
  | otherwise = Nothing
  where
    step n child = (n + 1 :: Int, if n == i then rewriteAt r is child else Just child)

genRules :: Gen [FixRule]
genRules = do
  n <- elements [1, 2, 3 :: Int]
  sequence [genRule ("r" <> T.pack (show k)) | k <- [1 .. n]]
  where
    genRule name = do
      lhs <- genOp ["x", "y"] 2
      rhs <- frequency [(1, genLeaf (pvars lhs)), (2, genOp (pvars lhs) 1)]
      pure (rule name lhs rhs)
    genOp vs d = frequency [(1, neg <$> genT vs (d - 1)), (2, add <$> genT vs (d - 1) <*> genT vs (d - 1))]
    genT vs d = if d <= 0 then genLeaf vs else frequency [(2, genLeaf vs), (1, genOp vs d)]
    genLeaf vs = elements ([a, zero] <> map pv vs)

pvars :: Fix ExprF -> [Text]
pvars (Fix l) = case l of
  PVar n -> [n]
  _ -> concatMap pvars l


type Canon = (Text, Text, [Int], Fix ExprF, Fix ExprF, Fix ExprF)

canonAll :: [FixRule] -> [Canon]
canonAll = sort . map canon . criticalPairs

canon :: CriticalPair -> Canon
canon cp = evalState body Map.empty
  where
    body = do
      p <- canonT (cpPeak cp)
      l <- canonT (cpLeft cp)
      r <- canonT (cpRight cp)
      pure (cpOuter cp, cpInner cp, cpPos cp, p, l, r)

canonJ :: Joinability -> Joinability
canonJ j = evalState (go j) Map.empty
  where
    go (Joined t) = Joined <$> canonT t
    go (NotJoined l r) = NotJoined <$> canonT l <*> canonT r
    go Unknown = pure Unknown

canonV :: PairVerdict -> PairVerdict
canonV (Joinable t) = Joinable (evalState (canonT t) Map.empty)
canonV v = v

canonT :: Fix ExprF -> State (Map.Map Text Text) (Fix ExprF)
canonT (Fix (PVar x)) = do
  seen <- get
  case Map.lookup x seen of
    Just y -> pure (pv y)
    Nothing -> do
      let y = "v" <> T.pack (show (Map.size seen))
      put (Map.insert x y seen)
      pure (pv y)
canonT (Fix l) = Fix <$> traverse canonT l

vars8 :: [Text] -> Map.Map Text Ty
vars8 ns = Map.fromList [(n, TBV 8) | n <- ns]

rule :: Text -> Fix ExprF -> Fix ExprF -> FixRule
rule n l r = FixRule n Generic (vars8 (pvars l <> pvars r)) l r Nothing

fg, gb, addZero, comm, notNot, deMorgan, xorSelf, xorLeft, guarded :: FixRule
fg = (rule "f-g" (notE (neg px)) a){frWidth = Fixed}
gb = (rule "g-b" (neg b) c){frWidth = Fixed}
addZero = rule "add-zero" (add px zero) px
comm = rule "comm" (add px py) (add py px)
notNot = rule "not-not" (notE (notE px)) px
deMorgan = rule "de-morgan-and" (notE (andE px py)) (orE (notE px) (notE py))
xorSelf = rule "xor-self" (xor px px) zero
xorLeft = rule "xor-left" (xor px py) px
guarded = (rule "guarded" (add px zero) px){frPre = Just (Fix (CmpF Ult px zero))}

a, b, c, zero, px, py :: Fix ExprF
a = Fix (VarF "a")
b = Fix (VarF "b")
c = Fix (VarF "c")
zero = Fix (LitF (U.VBV 8 0))
px = pv "x"
py = pv "y"

pv :: Text -> Fix ExprF
pv = Fix . PVar

neg, notE :: Fix ExprF -> Fix ExprF
neg = Fix . UnF Neg
notE = Fix . UnF Not

add, xor, andE, orE :: Fix ExprF -> Fix ExprF -> Fix ExprF
add l r = Fix (BinF Add l r)
xor l r = Fix (BinF Xor l r)
andE l r = Fix (BinF And l r)
orE l r = Fix (BinF Or l r)
