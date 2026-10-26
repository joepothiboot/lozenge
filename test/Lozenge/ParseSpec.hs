{-# LANGUAGE OverloadedStrings #-}

module Lozenge.ParseSpec (tests) where

import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import ExprGen (genExpr, shrinkExpr)
import Golden (goldenText)
import Lozenge.Expr
import Lozenge.Parse (parseExpr)
import Lozenge.Pretty (render)
import Props (props)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (forAllShrink, testProperty, (===))
import Text.Megaparsec (errorBundlePretty)

tests :: TestTree
tests =
  testGroup
    "Parse"
    [ testGroup "accepts" accepted,
      testGroup "rejects" (map rejects rejected),
      goldenText "error messages" "parse-errors.txt" (pure (T.concat (map errorReport rejected))),
      props $
        testProperty "parseExpr (render e) == Right e" $
          forAllShrink genExpr shrinkExpr $
            \e -> parseExpr (render e) === Right e
    ]

accepts :: Text -> Expr -> TestTree
accepts src e = testCase (show src) (parseExpr src @?= Right e)

rejects :: Text -> TestTree
rejects src = testCase (show src) (assertBool "expected a parse error" (isLeft (parseExpr src)))

errorReport :: Text -> Text
errorReport src =
  "--- " <> T.pack (show src) <> "\n" <> case parseExpr src of
    Left err -> T.pack (errorBundlePretty err)
    Right e -> "unexpectedly parsed as " <> T.pack (show e) <> "\n"

x, y :: Expr
x = Var "x"
y = Var "y"

accepted :: [TestTree]
accepted =
  [ accepts "x" x,
    accepts "  x \n" x,
    accepts "x_1" (Var "x_1"),
    accepts "_tmp" (Var "_tmp"),
    accepts "true" (Lit (VBool True)),
    accepts "false" (Lit (VBool False)),
    accepts "true1" (Var "true1"),
    accepts "(const 8 3)" (Lit (VBV 8 3)),
    accepts "(const 1 1)" (Lit (VBV 1 1)),
    accepts "(const 8 255)" (Lit (VBV 8 255)),
    accepts "(const 64 18446744073709551615)" (Lit (VBV 64 18446744073709551615)),
    accepts "(const 8 007)" (Lit (VBV 8 7)),
    accepts "(add x (const 8 3))" (Bin Add x (Lit (VBV 8 3))),
    accepts "(ite (ult x y) x y)" (Ite (Cmp Ult x y) x y),
    accepts "(= x y)" (Cmp Eq x y),
    accepts "(not x)" (Un Not x),
    accepts "(neg x)" (Un Neg x),
    accepts "(sub x y)" (Bin Sub x y),
    accepts "(mul x y)" (Bin Mul x y),
    accepts "(and x y)" (Bin And x y),
    accepts "(or x y)" (Bin Or x y),
    accepts "(xor x y)" (Bin Xor x y),
    accepts "(shl x y)" (Bin Shl x y),
    accepts "(lshr x y)" (Bin Lshr x y),
    accepts "(slt x y)" (Cmp Slt x y),
    accepts "( add\n\tx\n  y )" (Bin Add x y),
    accepts "(add(not x)y)" (Bin Add (Un Not x) y),
    -- operator names are only special in head position
    accepts "(add add const)" (Bin Add (Var "add") (Var "const")),
    -- the parser does not check sorts or widths
    accepts "(add true (const 16 0))" (Bin Add (Lit (VBool True)) (Lit (VBV 16 0)))
  ]

rejected :: [Text]
rejected =
  [ "",
    "   ",
    "()",
    "(",
    "(add x y",
    "(add x y))",
    "x y",
    "3",
    "1x",
    "(x)",
    "(foo x y)",
    "(addx y z)",
    "(add x)",
    "(add x y z)",
    "(not x y)",
    "(ite x y)",
    "(= x)",
    "(const 8)",
    "(const 8 3 4)",
    "(const x 3)",
    "(const 8 x)",
    "(const 8 -1)",
    "(const 0 0)",
    "(const 65 0)",
    "(const 8 256)",
    "(const 1 2)",
    "(const 64 18446744073709551616)",
    "(add x y) ; comment"
  ]
