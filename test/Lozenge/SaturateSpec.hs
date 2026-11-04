{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.SaturateSpec (tests) where

import Control.Monad.ST (ST, runST)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.TypeLits (natSing)
import Lozenge.EGraph
import Lozenge.EMatch
import Lozenge.EvalT (checkEnv, evalT)
import Lozenge.Expr (BinOp (..), CmpOp (..), Env, Expr (..), UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.ExprF (ExprF (..), fromTyped, toTyped)
import Lozenge.Extract
import Lozenge.Fix (Fix (..))
import Lozenge.Rule (Rule (..), RuleWidth (..), instantiate)
import Lozenge.Saturate
import Lozenge.Typecheck (Context)
import Lozenge.Typed (SingTy (..), SomeExpr (..), TExpr (..), Ty (..))
import Lozenge.Typed qualified as T
import Lozenge.VerifyBrute (renderVerdict, verifyBrute)
import Props (props)
import TExprGen (untyped)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, Property, checkCoverage, choose, conjoin, counterexample, cover, elements, forAll, frequency, oneof, testProperty, (===))

tests :: TestTree
tests =
  testGroup
    "Saturate"
    [ testGroup
        "ematch"
        [ testCase "(add ?x ?y) on (add a b) binds x to a and y to b" $
            sameMatches $ \g -> do
              s <- addTerm g (add a b)
              ids <- mapM (addTerm g) [a, b]
              ms <- ematch g (add (pv "x") (pv "y"))
              pure (ms, [(s, binds ["x", "y"] ids)]),
          testCase "a variable that occurs twice binds one class: (xor ?x ?x)" $
            withGraph
              ( \g -> do
                  _ <- addTerm g (xor a b)
                  before <- ematch g (xor (pv "x") (pv "x"))
                  ia <- addTerm g a
                  ib <- addTerm g b
                  merge g ia ib
                  rebuild g
                  after <- ematch g (xor (pv "x") (pv "x"))
                  s <- addTerm g (xor a b)
                  ia' <- addTerm g a
                  pure (before, after == [(s, binds ["x"] [ia'])])
              )
              @?= ([], True),
          testCase "it matches through classes: (neg (add ?x ?y)) on neg c, once c = a + b" $
            sameMatches $ \g -> do
              _ <- addTerm g (neg c)
              ic <- addTerm g c
              ab <- addTerm g (add a b)
              merge g ic ab
              rebuild g
              t <- addTerm g (neg c)
              ids <- mapM (addTerm g) [a, b]
              ms <- ematch g (neg (add (pv "x") (pv "y")))
              pure (ms, [(t, binds ["x", "y"] ids)]),
          testCase "a class holding (add a b) and (add b a) matches (add ?x ?y) twice" $
            sameMatches $ \g -> do
              s1 <- addTerm g (add a b)
              s2 <- addTerm g (add b a)
              merge g s1 s2
              rebuild g
              s <- addTerm g (add a b)
              ia <- addTerm g a
              ib <- addTerm g b
              ms <- ematch g (add (pv "x") (pv "y"))
              pure (ms, [(s, binds ["x", "y"] [ia, ib]), (s, binds ["x", "y"] [ib, ia])]),
          testCase "?x alone matches every class once" $
            sameMatches $ \g -> do
              _ <- addTerm g (add (neg a) (add a b))
              ms <- ematch g (pv "x")
              cs <- classes g
              pure (ms, [(i, binds ["x"] [i]) | (i, _) <- cs]),
          testCase "a term variable in a pattern matches only itself: (add a ?y)" $
            sameMatches $ \g -> do
              s0 <- addTerm g (add a (lit 0))
              s1 <- addTerm g (add a (lit 1))
              _ <- addTerm g (add c (lit 0))
              i0 <- addTerm g (lit 0)
              i1 <- addTerm g (lit 1)
              ms <- ematch g (add a (pv "y"))
              pure (ms, [(s0, binds ["y"] [i0]), (s1, binds ["y"] [i1])]),
          testCase "a literal in a pattern matches only itself: (add ?x 0)" $
            sameMatches $ \g -> do
              s0 <- addTerm g (add a (lit 0))
              _ <- addTerm g (add a (lit 1))
              s2 <- addTerm g (add c (lit 0))
              ia <- addTerm g a
              ic <- addTerm g c
              ms <- ematch g (add (pv "x") (lit 0))
              pure (ms, [(s0, binds ["x"] [ia]), (s2, binds ["x"] [ic])])
        ],
      testGroup
        "extract"
        [ testCase "astSize and shiftsAreCheap, node by node" $
            [ astSize (VarF "x"),
              astSize (BinF Add 1 1),
              astSize (UnF Neg 3),
              shiftsAreCheap (LitF (U.VBV 8 0)),
              shiftsAreCheap (BinF Shl 1 1),
              shiftsAreCheap (BinF Lshr 1 1),
              shiftsAreCheap (BinF Mul 1 1),
              shiftsAreCheap (BinF Add 1 1),
              shiftsAreCheap (IteF 1 1 1)
            ]
              @?= [1, 3, 4, 1, 3, 3, 6, 4, 5],
          testCase "with no merges, a term extracts to itself" $
            withGraph (\g -> addTerm g big >>= extract astSize g) @?= big,
          testCase "cycles: once f(a) = a, f(a) and f(f(a)) extract to a" $
            withGraph
              ( \g -> do
                  ffa <- addTerm g (neg (neg a))
                  fa <- addTerm g (neg a)
                  ia <- addTerm g a
                  merge g fa ia
                  rebuild g
                  mapM (extract astSize g) [fa, ffa]
              )
              @?= [a, a],
          testCase "a cycle through two classes: merge a f(f(a))" $
            twoClassCycle merge @?= twoClassCycleTerms,
          testCase "a cycle through two classes: merge f(f(a)) a" $
            twoClassCycle (\g ia ffa -> merge g ffa ia) @?= twoClassCycleTerms,
          testCase "the cost function decides: shifts or multiplications" $
            withGraph
              ( \g -> do
                  m <- addTerm g (mul x (lit 2))
                  s <- addTerm g (shl x (lit 1))
                  merge g m s
                  rebuild g
                  mapM (\cf -> extract cf g m) [shiftsAreCheap, mulsAreCheap]
              )
              @?= [shl x (lit 1), mul x (lit 2)],
          testCase "a stale id still extracts its class" $
            withGraph
              ( \g -> do
                  t <- addTerm g (add x (lit 0))
                  ix <- addTerm g x
                  merge g ix t
                  rebuild g
                  extract astSize g t
              )
              @?= x
        ],
      testGroup
        "loadRules"
        [ testCase "a wrong rule is refused, the valid ones kept" $ do
            let (ok, refused) = loadRules 8 [addZero, notToNeg, mulOne, addToOr]
            names ok @?= ["add-zero", "mul-one"]
            map fst refused @?= ["not-to-neg", "add-to-or"],
          testCase "the reason is the verdict" $
            snd (loadRules 8 [notToNeg]) @?= [("not-to-neg", renderVerdict (verifyBrute 8 notToNeg))],
          testCase "a rule too big to check is refused: assoc at width 8 has 24 bits" $
            let (ok, refused) = loadRules 8 [addAssoc] in (names ok, map fst refused) @?= ([], ["add-assoc"]),
          testCase "the same rule at width 4 is accepted" $
            names (fst (loadRules 4 [addAssoc])) @?= ["add-assoc"],
          testCase "a valid rule with a precondition is accepted" $
            names (fst (loadRules 8 [lshrSmall])) @?= ["lshr-small"],
          testCase "an accepted rule is instantiated at the width" $
            map checkedRule (fst (loadRules 4 [addZero])) @?= maybeToList (instantiate 4 addZero),
          testCase "the property's rule set loads with nothing refused" $
            map fst (snd (loadRules 8 propRules)) @?= [],
          testCase "a refused rule can't corrupt the graph: not a and neg a stay apart" $
            withGraph
              ( \g -> do
                  n1 <- addTerm g (Fix (UnF Not a))
                  n2 <- addTerm g (neg a)
                  _ <- saturate roomy (load8 [notToNeg, addZero]) g
                  equiv g n1 n2
              )
              @?= False
        ],
      testGroup
        "saturate"
        [ testCase "x*2 and x<<1 end up in one class; shiftsAreCheap picks the shift" $
            withGraph
              ( \g -> do
                  m <- addTerm g (mul x (lit 2))
                  _ <- saturate roomy (load8 [mul2ToShl]) g
                  s <- addTerm g (shl x (lit 1))
                  (,,) <$> equiv g m s <*> extract shiftsAreCheap g m <*> checkInvariants g
              )
              @?= (True, shl x (lit 1), []),
          testCase "(x+0)+0 extracts to x" $
            withGraph
              ( \g -> do
                  t <- addTerm g (add (add x (lit 0)) (lit 0))
                  _ <- saturate roomy (load8 [addZero]) g
                  extract astSize g t
              )
              @?= x,
          testCase "commutativity alone saturates: x + y in 2 iterations, 4 nodes" $
            withGraph (\g -> addTerm g (add x y) >> saturate roomy (load8 [addComm]) g)
              @?= SatReport Saturated 2 4 [],
          testCase "comm and assoc saturate 3 variables at 3^3 - 2^4 + 1 + 3 = 15 nodes" $
            let r = runAc 3 roomy in (satStop r, satNodes r) @?= (Saturated, 15),
          testCase "on 7 variables (1932 nodes saturated) the node limit stops it" $ do
            let r = runAc 7 roomy{limNodes = 400}
            satStop r @?= NodeLimit
            assertBool ("nodes " <> show (satNodes r) <> " should exceed 400") (satNodes r > 400),
          testCase "on 7 variables with 2 iterations allowed, the iteration limit stops it" $
            let r = runAc 7 roomy{limIters = 2} in (satStop r, satIterations r) @?= (IterLimit, 2),
          testCase "the scheduler bans rules that match too often, in rule order" $
            satBanned (runAc 4 roomy{limMatches = 1}) @?= ["add-comm", "add-assoc"],
          testCase "bans delay saturation but don't prevent it" $
            let r = runAc 4 roomy{limMatches = 4, limBan = 1, limIters = 100}
             in (satStop r, null (satBanned r)) @?= (Saturated, False),
          testCase "with a high threshold, nothing is banned" $
            satBanned (runAc 4 roomy) @?= [],
          testCase "saturating a saturated graph takes 1 iteration" $
            withGraph
              ( \g -> do
                  _ <- addTerm g (add (add x y) (lit 0))
                  _ <- saturate roomy (load8 [addComm, addZero]) g
                  satIterations <$> saturate roomy (load8 [addComm, addZero]) g
              )
              @?= 1,
          testCase "a precondition is decided on literals: lshr 3 4 is 0; lshr 200 4 and lshr x 4 are not" $
            withGraph
              ( \g -> do
                  ts <- mapM (addTerm g) [lshr (lit 3) (lit 4), lshr (lit 200) (lit 4), lshr x (lit 4)]
                  _ <- saturate roomy (load8 [lshrSmall]) g
                  z <- addTerm g (lit 0)
                  mapM (equiv g z) ts
              )
              @?= [True, False, False]
        ],
      props
        $ testProperty "the extracted term means the same as the input and costs no more"
        $ forAll genCase (checkCoverage . sameMeaning)
    ]

type Term = Fix ExprF

a, b, c, x, y :: Term
a = Fix (VarF "a")
b = Fix (VarF "b")
c = Fix (VarF "c")
x = Fix (VarF "x")
y = Fix (VarF "y")

pv :: Text -> Term
pv = Fix . PVar

lit :: Integer -> Term
lit = Fix . LitF . U.VBV 8

neg :: Term -> Term
neg = Fix . UnF Neg

add, mul, shl, lshr, xor :: Term -> Term -> Term
add p q = Fix (BinF Add p q)
mul p q = Fix (BinF Mul p q)
shl p q = Fix (BinF Shl p q)
lshr p q = Fix (BinF Lshr p q)
xor p q = Fix (BinF Xor p q)

big :: Term
big = Fix (IteF (Fix (CmpF Ult x y)) (add x (neg y)) (mul (lit 3) x))

sumOf :: Int -> Term
sumOf n = foldl1 add [Fix (VarF ("v" <> Text.pack (show i))) | i <- [0 .. n - 1]]

mulsAreCheap :: CostFn ExprF Int
mulsAreCheap (BinF Shl p q) = 100 + p + q
mulsAreCheap n = 1 + sum n

costOf :: CostFn ExprF Int -> Term -> Int
costOf cf (Fix l) = cf (fmap (costOf cf) l)

binds :: [Text] -> [ClassId] -> ClassSubst
binds vs ids = Map.fromList (zip vs ids)

rule :: Text -> [Text] -> Expr -> Expr -> Rule
rule name vs l r = Rule name Generic (Map.fromList [(v, TBV 8) | v <- vs]) l r Nothing

vx, vy, vz, vk :: Expr
vx = Var "x"
vy = Var "y"
vz = Var "z"
vk = Var "k"

k :: Integer -> Expr
k = Lit . U.VBV 8

addZero, mulOne, mulZero, xorSelf, subSelf, notNot, negNeg, mul2ToShl, addSelfToShl, addComm, mulComm, addAssoc, iteSame, ultSelf, eqSelf, lshrSmall :: Rule
addZero = rule "add-zero" ["x"] (Bin Add vx (k 0)) vx
mulOne = rule "mul-one" ["x"] (Bin Mul vx (k 1)) vx
mulZero = rule "mul-zero" ["x"] (Bin Mul vx (k 0)) (k 0)
xorSelf = rule "xor-self" ["x"] (Bin Xor vx vx) (k 0)
subSelf = rule "sub-self" ["x"] (Bin Sub vx vx) (k 0)
notNot = rule "not-not" ["x"] (Un Not (Un Not vx)) vx
negNeg = rule "neg-neg" ["x"] (Un Neg (Un Neg vx)) vx
mul2ToShl = rule "mul-2-to-shl" ["x"] (Bin Mul vx (k 2)) (Bin Shl vx (k 1))
addSelfToShl = rule "add-self-to-shl" ["x"] (Bin Add vx vx) (Bin Shl vx (k 1))
addComm = rule "add-comm" ["x", "y"] (Bin Add vx vy) (Bin Add vy vx)
mulComm = rule "mul-comm" ["x", "y"] (Bin Mul vx vy) (Bin Mul vy vx)
addAssoc = rule "add-assoc" ["x", "y", "z"] (Bin Add (Bin Add vx vy) vz) (Bin Add vx (Bin Add vy vz))
iteSame = (rule "ite-same" ["x"] (Ite (Var "p") vx vx) vx){ruleVars = Map.fromList [("p", TBool), ("x", TBV 8)]}
ultSelf = rule "ult-self" ["x"] (Cmp Ult vx vx) (Lit (U.VBool False))
eqSelf = rule "eq-self" ["x"] (Cmp Eq vx vx) (Lit (U.VBool True))
lshrSmall = (rule "lshr-small" ["x", "k"] (Bin Lshr vx vk) (k 0)){rulePre = Just (Cmp Ult vx (Bin Shl (k 1) vk))}

notToNeg, addToOr :: Rule
notToNeg = rule "not-to-neg" ["x"] (Un Not vx) (Un Neg vx)
addToOr = rule "add-to-or" ["x", "y"] (Bin Add vx vy) (Bin Or vx vy)

propRules :: [Rule]
propRules = [addZero, mulOne, mulZero, xorSelf, subSelf, notNot, negNeg, mul2ToShl, addSelfToShl, addComm, mulComm, iteSame, ultSelf, eqSelf, lshrSmall]

propChecked :: [CheckedRule]
propChecked = load8 propRules

load8 :: [Rule] -> [CheckedRule]
load8 = fst . loadRules 8

names :: [CheckedRule] -> [Text]
names = map (ruleName . checkedRule)

roomy :: Limits
roomy = Limits{limIters = 30, limNodes = 100000, limMatches = 100000, limBan = 2}

runAc :: Int -> Limits -> SatReport
runAc n lims = withGraph (\g -> addTerm g (sumOf n) >> saturate lims (fst (loadRules 4 [addComm, addAssoc])) g)

ctx8 :: Context
ctx8 = Map.fromList [("x", TBV 8), ("y", TBV 8)]

w8 :: SingTy ('TBV 8)
w8 = SBV (natSing @8)

genCase :: Gen (TExpr ('TBV 8), Env)
genCase = do
  t <- genBV (3 :: Int)
  wrapped <- elements [t, TBin Add t (lit8 0), TBin Mul t (lit8 2), TBin Xor t t]
  env <- Map.fromList <$> mapM (\v -> (,) v . U.VBV 8 <$> choose (0, 255)) ["x", "y"]
  pure (wrapped, env)
  where
    genBV 0 = leaf
    genBV d =
      frequency
        [ (2, leaf),
          (1, TUn <$> elements [Not, Neg] <*> genBV (d - 1)),
          (3, TBin <$> elements [Add, Sub, Mul, And, Xor, Shl, Lshr] <*> genBV (d - 1) <*> genBV (d - 1)),
          (1, TIte <$> (TCmp <$> elements [Eq, Ult] <*> genBV (d - 1) <*> genBV (d - 1)) <*> genBV (d - 1) <*> genBV (d - 1))
        ]
    leaf = oneof [pure (TVar w8 "x"), pure (TVar w8 "y"), lit8 <$> elements [0, 1, 2, 3, 255]]
    lit8 = TLit . T.VBV (natSing @8)

sameMeaning :: (TExpr ('TBV 8), Env) -> Property
sameMeaning (te, env) =
  cover 30 (costOf astSize small < costOf astSize input) "astSize found a cheaper term"
    $ counterexample ("astSize: " <> show small <> "\nshiftsAreCheap: " <> show fast)
    $ conjoin
      [ meaning small === expected,
        meaning fast === expected,
        counterexample "astSize cost went up" (costOf astSize small <= costOf astSize input),
        counterexample "shiftsAreCheap cost went up" (costOf shiftsAreCheap fast <= costOf shiftsAreCheap input)
      ]
  where
    input = fromTyped te
    (small, fast) = runST $ do
      g <- newEGraph
      i <- addTerm g input
      _ <- saturate Limits{limIters = 8, limNodes = 3000, limMatches = 1000, limBan = 2} propChecked g
      (,) <$> extract astSize g i <*> extract shiftsAreCheap g i
    tenvE = either (Left . show) Right (checkEnv ctx8 env)
    expected = (\tenv -> untyped (evalT tenv te)) <$> tenvE
    meaning t = do
      tenv <- tenvE
      SomeExpr _ te' <- either (Left . show) Right (toTyped ctx8 t)
      pure (untyped (evalT tenv te'))

twoClassCycle :: (forall s. EGraph ExprF s -> ClassId -> ClassId -> ST s ()) -> [Fix ExprF]
twoClassCycle mergeThem = withGraph $ \g -> do
  sumId <- addTerm g (add a (neg a))
  ffa <- addTerm g (neg (neg a))
  fa <- addTerm g (neg a)
  ia <- addTerm g a
  mergeThem g ia ffa
  rebuild g
  mapM (extract astSize g) [ia, fa, ffa, sumId]

twoClassCycleTerms :: [Fix ExprF]
twoClassCycleTerms = [a, neg a, a, add a (neg a)]

withGraph :: (forall s. EGraph ExprF s -> ST s r) -> r
withGraph k' = runST (newEGraph >>= k')

sameMatches :: (forall s. EGraph ExprF s -> ST s ([(ClassId, ClassSubst)], [(ClassId, ClassSubst)])) -> IO ()
sameMatches k' = let (got, want) = withGraph k' in sort got @?= sort want
