{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.EvalTSpec (tests) where

import Data.Functor (void)
import Data.Map.Strict qualified as Map
import ExprGen (testEnv)
import GHC.TypeLits (SNat, natSing)
import Lozenge.Eval (eval)
import Lozenge.EvalT
import Lozenge.Expr (BinOp (..), CmpOp (..), Env, UnOp (..))
import Lozenge.Expr qualified as U
import Lozenge.Typecheck (Context, TypeError (..))
import Lozenge.Typed
import Props (props)
import TExprGen (WellTyped (..), genWellTyped, shrinkWellTyped, testContext, untyped)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (counterexample, forAllShrink, testProperty, within, (===))

tests :: TestTree
tests =
  testGroup
    "EvalT"
    [ testGroup "checkEnv" checks,
      testGroup "evalT" evals,
      props $
        testGroup
          "properties"
          [ testProperty "evalT agrees with Phase 1 eval" $
              forAllShrink genWellTyped shrinkWellTyped $ \(WellTyped ctx (SomeExpr _ te) env) ->
                within 2_000_000 $ case checkEnv ctx env of
                  Left err -> counterexample ("checkEnv rejected the generated env: " <> show err) False
                  Right tenv -> Right (untyped (evalT tenv te)) === eval env (erase te)
          ]
    ]

-- checkEnv ------------------------------------------------------------------

accepts :: String -> Context -> Env -> TestTree
accepts name ctx env = testCase name (void (checkEnv ctx env) @?= Right ())

rejects :: String -> Context -> Env -> TypeError -> TestTree
rejects name ctx env err = testCase name (void (checkEnv ctx env) @?= Left err)

checks :: [TestTree]
checks =
  [ accepts "testEnv models testContext" testContext testEnv,
    accepts "undeclared variables are ignored" (Map.fromList [("x", TBV 8)]) testEnv,
    accepts "empty" Map.empty Map.empty,
    rejects "not bound" (Map.fromList [("w", TBV 8)]) testEnv (UnboundVar "w"),
    rejects "declared Bool, bound to a BV" (Map.fromList [("x", TBool)]) testEnv (ExpectedBool 8),
    rejects "declared BV, bound to a Bool" (Map.fromList [("p", TBV 8)]) testEnv ExpectedBV,
    rejects "declared BV 16, bound to a BV 8" (Map.fromList [("x", TBV 16)]) testEnv (WidthMismatch 16 8),
    rejects "ill-formed value" (Map.fromList [("x", TBV 8)]) (Map.fromList [("x", U.VBV 8 300)]) (InvalidValue (U.VBV 8 300)),
    rejects "declared width 0" (Map.fromList [("w", TBV 0)]) (Map.fromList [("w", U.VBV 0 0)]) (InvalidSort (TBV 0)),
    rejects "declared width 65" (Map.fromList [("w", TBV 65)]) (Map.fromList [("w", U.VBV 65 0)]) (InvalidSort (TBV 65)),
    -- order
    rejects "first variable by name" (Map.fromList [("b", TBool), ("a", TBV 8)]) Map.empty (UnboundVar "a"),
    rejects "sort before binding" (Map.fromList [("w", TBV 0)]) Map.empty (InvalidSort (TBV 0)),
    rejects "value before its sort" (Map.fromList [("x", TBool)]) (Map.fromList [("x", U.VBV 8 256)]) (InvalidValue (U.VBV 8 256))
  ]

-- evalT ---------------------------------------------------------------------

-- | testEnv, checked against testContext.
testTEnv :: TEnv
testTEnv = either (error . ("checkEnv rejected testEnv: " <>) . show) id (checkEnv testContext testEnv)

(==>) :: TExpr t -> Value t -> TestTree
te ==> v = testCase (show te) (evalT testTEnv te @?= v)

infix 1 ==>

evals :: [TestTree]
evals =
  [ bv w8 3 ==> VBV w8 3,
    TLit (VBool False) ==> VBool False,
    TBin Add (bv w8 200) (bv w8 100) ==> VBV w8 44,
    TBin Sub (bv w8 1) (bv w8 2) ==> VBV w8 255,
    TUn Neg (bv w8 1) ==> VBV w8 255,
    TBin Shl (bv w64 1) (bv w64 18446744073709551615) ==> VBV w64 0,
    TCmp Slt (bv w8 255) (bv w8 1) ==> VBool True,
    TCmp Ult (bv w8 255) (bv w8 1) ==> VBool False,
    TIte (TLit (VBool False)) (bv w8 1) (bv w8 2) ==> VBV w8 2,
    -- variables
    x ==> VBV w8 200,
    TVar SBool "p" ==> VBool True,
    TIte (TCmp Ult x y) x y ==> VBV w8 7,
    TBin Mul (TVar (SBV w64) "z") (TVar (SBV w64) "z") ==> VBV w64 1,
    -- not bound at this sort: zero
    TVar (SBV w8) "nope" ==> VBV w8 0,
    TVar SBool "x" ==> VBool False,
    TVar (SBV (natSing @16)) "x" ==> VBV (natSing @16) 0,
    testCase "variables the context does not declare read as zero" $
      either (error . show) (`evalT` y) (checkEnv (Map.fromList [("x", TBV 8)]) testEnv) @?= VBV w8 0
  ]

w8 :: SNat 8
w8 = natSing

w64 :: SNat 64
w64 = natSing

bv :: SNat w -> Integer -> TExpr ('TBV w)
bv w v = TLit (VBV w v)

x, y :: TExpr ('TBV 8)
x = TVar (SBV w8) "x"
y = TVar (SBV w8) "y"
