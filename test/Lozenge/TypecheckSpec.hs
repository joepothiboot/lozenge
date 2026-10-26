{-# LANGUAGE OverloadedStrings #-}

module Lozenge.TypecheckSpec (tests) where

import Data.Bifunctor (first)
import Data.Either (isLeft)
import Data.Functor (void)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import ExprGen (genExpr, shrinkExpr, testEnv)
import Golden (goldenText)
import Lozenge.Eval qualified as E
import Lozenge.EvalT (checkEnv, evalT)
import Lozenge.Expr
import Lozenge.Typecheck
import Lozenge.Typed (SomeExpr (..), Ty (..), erase)
import Props (props)
import TExprGen (WellTyped (..), genWellTyped, shrinkWellTyped, testContext, tyOf, untyped)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (counterexample, cover, forAllShrink, testProperty, (===))

tests :: TestTree
tests =
  testGroup
    "Typecheck"
    [ testGroup "accepts" [testCase (show e) (fmap summary (typecheck ctx e) @?= Right (ty, e)) | (e, ty) <- accepted],
      testGroup "rejects" [testCase (show e) (fmap sortOf (typecheck ctx e) @?= Left err) | (e, err) <- rejected],
      goldenText "golden" "typecheck.txt" (pure (T.unlines (map line (map fst accepted ++ map fst rejected)))),
      props $
        testGroup
          "properties"
          [ testProperty "accepts generated well-typed terms, and erase undoes it" $
              forAllShrink genWellTyped shrinkWellTyped $ \(WellTyped c (SomeExpr s te) _) ->
                let e = erase te
                 in fmap summary (typecheck c e) === Right (tyOf s, e),
            testProperty "evalT of its result agrees with Phase 1 eval" $
              forAllShrink genWellTyped shrinkWellTyped $ \(WellTyped c (SomeExpr _ te) env) ->
                let e = erase te
                 in case (typecheck c e, checkEnv c env) of
                      (Right (SomeExpr _ te'), Right tenv) -> Right (untyped (evalT tenv te')) === E.eval env e
                      (r, t) -> counterexample ("typecheck: " <> show r <> "\ncheckEnv: " <> show t) False,
            testProperty "fails exactly where Phase 1 eval fails, with the same error" $
              forAllShrink genExpr shrinkExpr $ \e ->
                let got = void (typecheck testContext e)
                 in cover 10 (isLeft got) "ill-typed" $
                      got === first staticError (void (E.eval testEnv e))
          ]
    ]
  where
    summary (SomeExpr s te) = (tyOf s, erase te)
    sortOf (SomeExpr s _) = tyOf s
    line e = T.pack (show e <> "\n  " <> show (typecheck ctx e))

-- | testContext, plus two declarations whose widths are ill formed.
ctx :: Context
ctx = testContext <> Map.fromList [("w0", TBV 0), ("w65", TBV 65)]

-- | The error Phase 1 reports for the same mistake.
staticError :: E.EvalError -> TypeError
staticError (E.UnboundVar x) = UnboundVar x
staticError E.ExpectedBV = ExpectedBV
staticError (E.ExpectedBool w) = ExpectedBool w
staticError (E.WidthMismatch l r) = WidthMismatch l r
staticError (E.InvalidValue v) = InvalidValue v

bv :: Int -> Integer -> Expr
bv w v = Lit (VBV w v)

tt :: Expr
tt = Lit (VBool True)

accepted :: [(Expr, Ty)]
accepted =
  [ (Var "x", TBV 8),
    (Var "p", TBool),
    (Lit (VBool False), TBool),
    (bv 1 1, TBV 1),
    (bv 64 18446744073709551615, TBV 64),
    (bv 13 8191, TBV 13),
    (Un Not (Var "z"), TBV 64),
    (Bin Add (Var "x") (bv 8 1), TBV 8),
    (Bin Shl (Var "b") (Var "b"), TBV 1),
    (Cmp Eq (Var "x") (Var "y"), TBool),
    (Cmp Slt (Var "z") (bv 64 0), TBool),
    (Ite (Var "p") (Var "x") (Var "y"), TBV 8),
    -- the comparison is at width 1, the result at width 64
    (Ite (Cmp Ult (Var "b") (bv 1 1)) (Var "z") (bv 64 0), TBV 64),
    (Bin Mul (Ite (Var "q") (Var "x") (Un Neg (Var "y"))) (bv 8 3), TBV 8)
  ]

rejected :: [(Expr, TypeError)]
rejected =
  [ -- width mismatch in add
    (Bin Add (Var "x") (Var "z"), WidthMismatch 8 64),
    (Bin Add (bv 16 1) (Var "x"), WidthMismatch 16 8),
    -- ite on a BV
    (Ite (Var "x") (Var "x") (Var "y"), ExpectedBool 8),
    (Ite (bv 1 1) (bv 8 0) (bv 8 1), ExpectedBool 1),
    -- mixing widths in eq
    (Cmp Eq (Var "x") (Var "z"), WidthMismatch 8 64),
    (Cmp Eq (bv 8 0) (bv 16 0), WidthMismatch 8 16),
    -- other sort errors
    (Bin Add (Var "p") (Var "x"), ExpectedBV),
    (Un Neg tt, ExpectedBV),
    (Cmp Ult (Var "x") (Var "p"), ExpectedBV),
    (Cmp Eq (Var "p") (Var "q"), ExpectedBV),
    (Ite (Var "p") (Var "p") (Var "q"), ExpectedBV),
    (Bin Add (Cmp Eq (Var "x") (Var "y")) (Var "x"), ExpectedBV),
    (Ite (Var "p") (Var "x") (Var "z"), WidthMismatch 8 64),
    -- leaves
    (Var "nope", UnboundVar "nope"),
    (Var "w0", InvalidSort (TBV 0)),
    (Bin Add (Var "w65") (Var "w65"), InvalidSort (TBV 65)),
    (bv 8 256, InvalidValue (VBV 8 256)),
    (bv 8 (-1), InvalidValue (VBV 8 (-1))),
    (bv 0 0, InvalidValue (VBV 0 0)),
    (bv 65 0, InvalidValue (VBV 65 0)),
    (bv (-1) 0, InvalidValue (VBV (-1) 0)),
    -- order: operands left to right, then the node's sorts, then its widths
    (Bin Add tt (Var "nope"), UnboundVar "nope"),
    (Cmp Slt (Var "w0") (Var "nope"), InvalidSort (TBV 0)),
    (Bin Add (bv 16 0) (Bin Add (Var "p") (Var "x")), ExpectedBV),
    (Ite (Var "x") (bv 8 0) (bv 16 0), ExpectedBool 8),
    (Ite (Var "p") (Var "q") (Var "z"), ExpectedBV)
  ]
