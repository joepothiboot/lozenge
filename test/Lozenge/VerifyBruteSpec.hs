{-# LANGUAGE OverloadedStrings #-}

module Lozenge.VerifyBruteSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Lozenge.Eval (eval)
import Lozenge.Expr
import Lozenge.Rule
import Lozenge.Typecheck (Context)
import Lozenge.Typed (Ty (..))
import Lozenge.VerifyBrute
import Props (props)
import TExprGen (genRule, genValue, untyped, withSing)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (Gen, choose, counterexample, cover, forAll, property, testProperty, (===))

tests :: TestTree
tests =
  testGroup
    "VerifyBrute"
    [ testGroup
        "renderVerdict"
        [ testCase "valid" $ renderVerdict Valid @?= "valid",
          testCase "unsupported" $ renderVerdict (Unsupported "too many") @?= "unsupported: too many",
          testCase "the example format, variables in name order" $
            renderVerdict (Counterexample (env [("y", VBV 8 1), ("x", VBV 8 3)]) (VBV 8 4) (VBV 8 5))
              @?= "x = 0x03, y = 0x01: lhs = 0x04, rhs = 0x05",
          testCase "padding to ceiling (w / 4) digits" $
            renderVerdict (Counterexample (env [("a", VBV 1 1), ("b", VBV 5 3), ("c", VBV 12 0xabc)]) (VBV 64 (2 ^ (64 :: Int) - 1)) (VBV 64 0))
              @?= "a = 0x1, b = 0x03, c = 0xabc: lhs = 0xffffffffffffffff, rhs = 0x0000000000000000",
          testCase "Bool values" $
            renderVerdict (Counterexample (env [("p", VBool True)]) (VBool False) (VBool True))
              @?= "p = true: lhs = false, rhs = true",
          testCase "no variables" $
            renderVerdict (Counterexample Map.empty (VBool True) (VBool False)) @?= "lhs = true, rhs = false"
        ],
      testGroup "valid" [verdict 8 r "valid" | r <- [addZero, addComm, shl1ToAdd, deMorgan, ultSelf, iteSame]],
      testGroup
        "invalid"
        [ verdict 8 subComm "x = 0x00, y = 0x01: lhs = 0xff, rhs = 0x01",
          verdict 8 shl1ToMulSelf "x = 0x01: lhs = 0x02, rhs = 0x01",
          verdict 8 ultToSlt "x = 0x00, y = 0x80: lhs = true, rhs = false",
          verdict 8 iteSwap "p = false, x = 0x00, y = 0x01: lhs = 0x01, rhs = 0x00"
        ],
      testGroup
        "precondition"
        [ verdict 8 shlLshr "valid",
          verdict 8 shlLshr{rulePre = Nothing} "x = 0x80: lhs = 0x00, rhs = 0x80"
        ],
      testGroup
        "width-dependent"
        [ verdict 4 shl4Zero "valid",
          verdict 8 shl4Zero "x = 0x01: lhs = 0x10, rhs = 0x00",
          verdict 4 deMorgan "valid",
          -- Fixed rules ignore the width argument, even an out-of-range one.
          verdict 4 subComm "x = 0x00, y = 0x01: lhs = 0xff, rhs = 0x01",
          verdict 0 addZero "valid"
        ],
      testGroup
        "unsupported"
        [ testCase "exactly 2^20 assignments is allowed" $ verifyBrute 10 addComm{ruleWidth = Generic} @?= Valid,
          unsupported "2^22 assignments" 11 addComm{ruleWidth = Generic},
          unsupported "three 8-bit variables" 8 (rule "three" Fixed [("x", TBV 8), ("y", TBV 8), ("z", TBV 8)] x x),
          unsupported "a 64-bit variable" 8 (rule "wide" Fixed [("x", TBV 64)] x x),
          unsupported "Generic at width 0" 0 shl4Zero,
          unsupported "Generic at width 65" 65 shl4Zero,
          unsupported "lhs Bool, rhs BV" 8 (rule "sorts" Fixed bv8xy (Cmp Ult x y) x),
          unsupported "precondition is not Bool" 8 addZero{rulePre = Just x},
          unsupported "ill-typed lhs" 8 (rule "ill" Fixed bv8xy (Bin Add x (bv 16 0)) x),
          unsupported "undeclared variable" 8 (rule "unbound" Fixed bv8xy (Var "z") x)
        ],
      props $
        testProperty "Valid means lhs and rhs evaluate equal on random assignments" $
          forAll genRule $ \r -> forAll (choose (1, 5)) $ \w ->
            let v = verifyBrute w r
             in cover 10 (v == Valid) "valid" $ case (v, instantiate w r) of
                  (Valid, Just r') -> forAll (genEnv (ruleVars r')) $ \e ->
                    counterexample ("instantiated: " <> show r') $
                      case traverse (eval e) (rulePre r') of
                        Right (Just (VBool False)) -> property True
                        _ -> eval e (ruleLhs r') === eval e (ruleRhs r')
                  (Valid, Nothing) -> counterexample "Valid, but instantiate gave Nothing" False
                  _ -> property True
    ]

verdict :: Int -> Rule -> Text -> TestTree
verdict w r expected = testCase (show (ruleName r) <> " at width " <> show w) (renderVerdict (verifyBrute w r) @?= expected)

unsupported :: String -> Int -> Rule -> TestTree
unsupported name w r = testCase name $ case verifyBrute w r of
  Unsupported _ -> pure ()
  other -> assertBool ("expected Unsupported, got " <> show other) False

env :: [(Text, Value)] -> Env
env = Map.fromList

rule :: Text -> RuleWidth -> [(Text, Ty)] -> Expr -> Expr -> Rule
rule name w vars lhs rhs = Rule name w (Map.fromList vars) lhs rhs Nothing

bv :: Int -> Integer -> Expr
bv w v = Lit (VBV w v)

x, y, p :: Expr
x = Var "x"
y = Var "y"
p = Var "p"

bv8x, bv8xy :: [(Text, Ty)]
bv8x = [("x", TBV 8)]
bv8xy = [("x", TBV 8), ("y", TBV 8)]

addZero, addComm, shl1ToAdd, deMorgan, ultSelf, iteSame :: Rule
addZero = rule "add-zero" Fixed bv8x (Bin Add x (bv 8 0)) x
addComm = rule "add-comm" Fixed bv8xy (Bin Add x y) (Bin Add y x)
shl1ToAdd = rule "shl-1-to-add" Fixed bv8x (Bin Shl x (bv 8 1)) (Bin Add x x)
deMorgan = rule "de-morgan" Generic bv8xy (Un Not (Bin And x y)) (Bin Or (Un Not x) (Un Not y))
ultSelf = rule "ult-self" Fixed bv8x (Cmp Ult x x) (Lit (VBool False))
iteSame = rule "ite-same" Fixed [("p", TBool), ("x", TBV 8)] (Ite p x x) x

subComm, shl1ToMulSelf, ultToSlt, iteSwap :: Rule
subComm = rule "sub-comm" Fixed bv8xy (Bin Sub x y) (Bin Sub y x)
shl1ToMulSelf = rule "shl-1-to-mul-self" Fixed bv8x (Bin Shl x (bv 8 1)) (Bin Mul x x)
ultToSlt = rule "ult-to-slt" Fixed bv8xy (Cmp Ult x y) (Cmp Slt x y)
iteSwap = rule "ite-swap" Fixed [("p", TBool), ("x", TBV 8), ("y", TBV 8)] (Ite p x y) (Ite p y x)

shlLshr :: Rule
shlLshr =
  (rule "shl-lshr" Fixed bv8x (Bin Lshr (Bin Shl x (bv 8 1)) (bv 8 1)) x)
    { rulePre = Just (Cmp Ult x (bv 8 128))
    }

shl4Zero :: Rule
shl4Zero = rule "shl-4-zero" Generic bv8x (Bin Shl x (bv 8 4)) (bv 8 0)

genEnv :: Context -> Gen Env
genEnv = traverse (\ty -> withSing ty (fmap untyped . genValue))
