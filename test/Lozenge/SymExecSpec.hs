{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.SymExecSpec (tests) where

import Control.Monad (ap)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import GHC.TypeLits (SNat, natSing)
import Lozenge.Expr (BinOp (..), CmpOp (..), UnOp (..))
import Lozenge.Smt (smtName, toSmt)
import Lozenge.Solver (SolverResult (..), runZ3)
import Lozenge.SymExec
import Lozenge.Typed
import Props (props)
import TExprGen (genTExpr, testContext)
import Test.Tasty (TestName, TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, arbitrary, forAll, listOf, sized, testProperty)
import Z3 (requireZ3)

tests :: TestTree
tests =
  testGroup
    "SymExec"
    [ testGroup
        "andC and notC"
        [ testCase "true on the left is dropped" $ andC true p @?~ p,
          testCase "true on the right is dropped" $ andC p true @?~ p,
          z3 "andC is and" $ mapM_ (\(a, b) -> proves (eq (andC a b) ("(and " <> toSmt a <> " " <> toSmt b <> ")"))) pairs,
          z3 "notC is not" $ mapM_ (\a -> proves (eq (notC a) ("(not " <> toSmt a <> ")"))) [p, lt, false]
        ],
      testGroup
        "mrgIte"
        [ z3 "BV" $ proves (eq (mrgIte lt x y) "(ite (bvult v_x v_y) v_x v_y)"),
          z3 "Bool" $ proves (eq (mrgIte p q lt) "(ite v_p v_q (bvult v_x v_y))"),
          z3 "Bool, literal branches" $ proves (eq (mrgIte p false true) "(not v_p)")
        ],
      testGroup
        "Union"
        [ testCase "fmap keeps guards and order" $ fmap (+ 1) ltGt @?~ Union [(lt, 2), (gt, 3 :: Int)],
          testCase "pure" $ pure 'a' @?~ Union [(true, 'a')],
          testCase "bind: andC of outer and inner guard, outer order first" $
            (Union [(p, 1), (notC p, 2)] >>= step)
              @?~ Union [(andC p lt, 1), (andC p gt, 2), (andC (notC p) lt, 2), (andC (notC p) gt, 3 :: Int)],
          testCase "bind on no entries" $ (Union [] >>= step) @?~ Union [],
          testCase "<*> agrees with ap" $ (fs <*> ltGt) @?~ (fs `ap` ltGt),
          props $ testProperty "left identity" $ forAll genUnion $ \u -> show (pure () >>= const u) == show u,
          props $ testProperty "right identity" $ forAll genUnion $ \u -> show (u >>= pure) == show u,
          props $ testProperty "fmap id" $ forAll genUnion $ \u -> show (fmap id u) == show u
        ],
      testGroup
        "merge"
        [ testCase "no entries" $ length (unUnion (merge (Union [] :: Union (TExpr ('TBV 8))))) @?= 0,
          testCase "one entry comes back unchanged" $ merge (Union [(lt, x)]) @?~ Union [(lt, x)],
          z3 "three BV entries" $ do
            (g, v) <- single (merge (Union [(lt, y), (gt, x), (TCmp Eq x y, x)]))
            proves (same v (TIte lt y x))
            proves (same g true),
          z3 "two Bool entries" $ do
            (g, v) <- single (merge (Union [(p, q), (notC p, lt)]))
            proves (eq v "(ite v_p v_q (bvult v_x v_y))")
            proves (same g true),
          z3 "guard is the disjunction" $ do
            (g, _) <- single (merge (Union [(lt, x), (gt, y)]))
            proves (eq g "(not (= v_x v_y))")
        ],
      testGroup
        "subst"
        [ testCase "every occurrence" $
            subst (Map.fromList [("x", c 1)]) (TBin Add x (TUn Neg x)) @?~ TBin Add (c 1) (TUn Neg (c 1)),
          testCase "under a comparison and an ite" $
            subst (Map.fromList [("x", y)]) (TCmp Ult x (TIte p x y)) @?~ TCmp Ult y (TIte p y y),
          testCase "one pass: x and y swap" $
            subst (Map.fromList [("x", y), ("y", x)]) (TBin Sub x y) @?~ TBin Sub y x,
          testCase "unbound and Bool variables stay" $
            subst (Map.fromList [("x", c 1)]) (TIte p y x) @?~ TIte p y (c 1),
          testCase "a variable of another width stays" $
            subst (Map.fromList [("x", c 1)]) (TCmp Eq x16 x16) @?~ TCmp Eq x16 x16
        ],
      testGroup
        "symExec"
        [ testCase "empty program" $ symExec [] @?~ Union [(true, Env Map.empty true)],
          testCase "straight line, each assignment sees the last" $
            symExec [Assign "x" (TBin Add x (c 1)), Assign "x" (TBin Add x (c 1))]
              @?~ Union [(true, Env (Map.fromList [("x", TBin Add (TBin Add x (c 1)) (c 1))]) true)],
          testCase "two branches give two paths before merging" $ length (unUnion (symExec maxProg)) @?= 2,
          testCase "two ifs in a row give four paths" $ length (unUnion (symExec (maxProg <> maxProg))) @?= 4,
          z3 "two branches merge into one ite, equal to the hand-written max" $ do
            (g, env) <- single (merge (symExec maxProg))
            Map.keys (envVars env) @?= ["m"]
            v <- var env "m"
            proves (same v (TIte lt y x))
            proves (same g true)
            proves (same (envOk env) true),
          z3 "a variable one branch leaves alone keeps its input there" $ do
            (_, env) <- single (merge (symExec [If p [Assign "m" (c 0)] []]))
            v <- var env "m"
            proves (same v (TIte p (c 0) m)),
          z3 "the condition sees earlier assignments" $ do
            (_, env) <- single (merge (symExec [Assign "x" (c 0), If lt [Assign "m" (c 1)] [Assign "m" (c 2)]]))
            v <- var env "m"
            proves (same v (TIte (TCmp Ult (c 0) y) (c 1) (c 2))),
          z3 "nested ifs" $ do
            let prog = [If p [If q [Assign "m" (c 1)] [Assign "m" (c 2)]] [Assign "m" (c 3)]]
            length (unUnion (symExec prog)) @?= 3
            (g, env) <- single (merge (symExec prog))
            v <- var env "m"
            proves (same v (TIte p (TIte q (c 1) (c 2)) (c 3)))
            proves (same g true),
          z3 "an assert that always holds" $ do
            (_, env) <- single (merge (symExec (maxProg <> [Assert (notC (TCmp Ult m x))])))
            proves (same (envOk env) true),
          z3 "an assert that can fail" $ do
            (_, env) <- single (merge (symExec [If p [Assign "m" x] [Assign "m" y], Assert (TCmp Ult m y)]))
            proves (eq (envOk env) "(ite v_p (bvult v_x v_y) false)")
        ]
    ]

-- m := max x y, unsigned.
maxProg :: Program 8
maxProg = [If lt [Assign "m" y] [Assign "m" x]]

step :: Int -> Union Int
step n = Union [(lt, n), (gt, n + 1)]

ltGt :: Union Int
ltGt = Union [(lt, 1), (gt, 2)]

fs :: Union (Int -> Int)
fs = Union [(p, (+ 1)), (notC p, (* 2))]

pairs :: [(Cond, Cond)]
pairs = [(p, q), (lt, gt), (p, false), (false, p), (true, true)]

-- Not disjoint: the identity laws do not need the invariant.
genUnion :: Gen (Union Int)
genUnion = Union <$> listOf ((,) <$> sized (genTExpr testContext SBool) <*> arbitrary)

-- TExpr has no Eq instance, and the derived Show shows the whole term.
(@?~) :: (Show a) => a -> a -> Assertion
a @?~ b = show a @?= show b

infix 1 @?~

single :: (Show a) => Union a -> IO (Cond, a)
single (Union [e]) = pure e
single u = assertFailure ("expected one entry, got " <> show u)

var :: Env 8 -> Text -> IO (TExpr ('TBV 8))
var env n = maybe (assertFailure (T.unpack n <> " is unbound in " <> show env)) pure (Map.lookup n (envVars env))

z3 :: TestName -> IO () -> TestTree
z3 name t = requireZ3 name (t >> pure "")

-- An SMT-LIB formula for a = b.
same :: TExpr t -> TExpr t -> Text
same a b = eq a (toSmt b)

eq :: TExpr t -> Text -> Text
eq a b = "(= " <> toSmt a <> " " <> b <> ")"

-- z3 must find no assignment of x, y, m, p and q that makes f false.
proves :: Text -> IO ()
proves f = do
  r <- runZ3 5000 (T.unlines (decls <> ["(assert (not " <> f <> "))", "(check-sat)"]))
  case r of
    Unsat -> pure ()
    other -> assertFailure ("not valid: " <> T.unpack f <> "\nz3: " <> show other)
  where
    decls =
      ["(set-logic QF_BV)"]
        <> ["(declare-const " <> smtName n <> " (_ BitVec 8))" | n <- ["x", "y", "m"]]
        <> ["(declare-const " <> smtName n <> " Bool)" | n <- ["p", "q"]]

w8 :: SNat 8
w8 = natSing

c :: Integer -> TExpr ('TBV 8)
c = TLit . VBV w8

x, y, m :: TExpr ('TBV 8)
x = TVar (SBV w8) "x"
y = TVar (SBV w8) "y"
m = TVar (SBV w8) "m"

x16 :: TExpr ('TBV 16)
x16 = TVar (SBV natSing) "x"

p, q, lt, gt, true, false :: Cond
p = TVar SBool "p"
q = TVar SBool "q"
lt = TCmp Ult x y
gt = TCmp Ult y x
true = TLit (VBool True)
false = TLit (VBool False)
