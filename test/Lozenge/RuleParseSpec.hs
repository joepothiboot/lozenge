{-# LANGUAGE OverloadedStrings #-}

module Lozenge.RuleParseSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golden (goldenText)
import Lozenge.Expr
import Lozenge.Rule
import Lozenge.RuleParse
import Lozenge.Typed (Ty (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))
import Text.Megaparsec (errorBundlePretty)

tests :: TestTree
tests =
  testGroup
    "RuleParse"
    [ testGroup "accepts" [testCase (show src) (parseRules "t.rules" src @?= Right rs) | (src, rs) <- accepted],
      testGroup "mkRule rejects" [testCase (T.unpack msg) (fmap ruleName (mkRule "r" l r pre) @?= Left msg) | (l, r, pre, msg) <- mkRejected],
      testGroup "parseRules reports mkRule errors" [reportsAt src loc msg | (src, loc, msg) <- reported],
      testGroup "rejects" [rejects src | src <- syntaxRejected],
      goldenText "error messages" "rule-errors.txt" (pure (T.concat (map errorReport (syntaxRejected ++ [src | (src, _, _) <- reported]))))
    ]

rejects :: Text -> TestTree
rejects src = testCase (show src) $ case parseRules "t.rules" src of
  Left _ -> pure ()
  Right rs -> assertFailure ("expected a parse error, got " <> show rs)

reportsAt :: Text -> Text -> Text -> TestTree
reportsAt src loc msg = testCase (show src) $ case parseRules "t.rules" src of
  Left err
    | let s = T.pack (errorBundlePretty err), loc `T.isPrefixOf` s && msg `T.isInfixOf` s -> pure ()
    | otherwise -> assertFailure ("expected " <> show loc <> " and " <> show msg <> ", got\n" <> errorBundlePretty err)
  Right rs -> assertFailure ("expected a parse error, got " <> show rs)

errorReport :: Text -> Text
errorReport src =
  "--- " <> T.pack (show src) <> "\n" <> case parseRules "t.rules" src of
    Left err -> T.pack (errorBundlePretty err)
    Right rs -> "unexpectedly parsed as " <> T.pack (show rs) <> "\n"

x, y, p :: Expr
x = Var "x"
y = Var "y"
p = Var "p"

bv :: Int -> Integer -> Expr
bv w v = Lit (VBV w v)

pw :: Integer -> Expr
pw = bv 0

rule :: Text -> RuleWidth -> [(Text, Ty)] -> Expr -> Expr -> Maybe Expr -> Rule
rule name w vars = Rule name w (Map.fromList vars)

accepted :: [(Text, [Rule])]
accepted =
  [ ("", []),
    ("  \n; only a comment\n", []),
    ( "(rule add-zero (add ?x (const 8 0)) => ?x)",
      [rule "add-zero" Fixed [("x", TBV 8)] (Bin Add x (bv 8 0)) x Nothing]
    ),
    ( "(rule add-zero (add ?x (const w 0)) => ?x)",
      [rule "add-zero" Generic [("x", TBV 64)] (Bin Add x (bv 64 0)) x Nothing]
    ),
    ( "(rule shl-1-to-add (shl ?x (const 8 1)) => (add ?x ?x))",
      [rule "shl-1-to-add" Fixed [("x", TBV 8)] (Bin Shl x (bv 8 1)) (Bin Add x x) Nothing]
    ),
    ( "(rule ult-self (ult ?x ?x) => false)",
      [rule "ult-self" Generic [("x", TBV 64)] (Cmp Ult x x) (Lit (VBool False)) Nothing]
    ),
    ( "(rule ite-same (ite ?p ?x ?x) => ?x)",
      [rule "ite-same" Generic [("p", TBool), ("x", TBV 64)] (Ite p x x) x Nothing]
    ),
    ( "(rule shl-lshr (lshr (shl ?x (const 4 1)) (const 4 1)) => ?x\n  :if (ult ?x (const 4 8)))",
      [ rule "shl-lshr" Fixed [("x", TBV 4)] (Bin Lshr (Bin Shl x (bv 4 1)) (bv 4 1)) x (Just (Cmp Ult x (bv 4 8)))
      ]
    ),
    ( "(rule big (and ?x (const w 255)) => ?x)",
      [rule "big" Generic [("x", TBV 64)] (Bin And x (bv 64 255)) x Nothing]
    ),
    ( "; header\n(rule a_1 (not (not ?x)) => ?x) ; trailing\n\n(rule B-2 (neg (neg ?x)) => ?x)\n",
      [ rule "a_1" Generic [("x", TBV 64)] (Un Not (Un Not x)) x Nothing,
        rule "B-2" Generic [("x", TBV 64)] (Un Neg (Un Neg x)) x Nothing
      ]
    ),
    ( "(rule\n\tws\n  (add ?x ?y)=>(add ?y ?x))",
      [rule "ws" Generic [("x", TBV 64), ("y", TBV 64)] (Bin Add x y) (Bin Add y x) Nothing]
    )
  ]

mkRejected :: [(Expr, Expr, Maybe Expr, Text)]
mkRejected =
  [ (Bin Add x (pw 1), bv 8 0, Nothing, "rule r: mixes the width placeholder w with width 8"),
    (Bin Add x (bv 16 0), Bin Add x (bv 8 0), Nothing, "rule r: uses widths 8 and 16; a rule uses one width"),
    (Un Not x, y, Nothing, "rule r: rhs uses ?y, which the lhs does not bind"),
    (Un Not x, x, Just (Cmp Ult x (Var "z")), "rule r: precondition uses ?z, which the lhs does not bind"),
    (Ite p p x, x, Nothing, "rule r: ?p is used as both Bool and BV"),
    (x, x, Nothing, "rule r: cannot infer the sort of ?x"),
    (Bin Add x (Lit (VBool True)), x, Nothing, "rule r: lhs is ill-typed: ExpectedBV"),
    (Un Not x, Ite (pw 1) x x, Nothing, "rule r: rhs is ill-typed: ExpectedBool 64"),
    (Bin Add x (pw (2 ^ (64 :: Int))), x, Nothing, "rule r: lhs is ill-typed: InvalidValue (VBV 64 18446744073709551616)"),
    (Cmp Ult x y, x, Nothing, "rule r: lhs has sort Bool but rhs has sort BV w"),
    (Bin Add x (bv 8 0), Cmp Eq x x, Nothing, "rule r: lhs has sort BV 8 but rhs has sort Bool"),
    (Un Not x, Un Not x, Just (Bin Add x x), "rule r: precondition has sort BV w, expected Bool"),
    (Bin Add x (bv 8 0), Bin Add y (bv 16 0), Nothing, "rule r: uses widths 8 and 16; a rule uses one width"),
    (x, y, Nothing, "rule r: rhs uses ?y, which the lhs does not bind")
  ]

reported :: [(Text, Text, Text)]
reported =
  [ ("(rule r ?x => ?x)", "t.rules:1:1:", "rule r: cannot infer the sort of ?x"),
    ("\n  (rule r (ult ?x ?y) => ?x)", "t.rules:2:3:", "rule r: lhs has sort Bool but rhs has sort BV w"),
    ("(rule r (add ?x (const 8 0)) => (add ?x (const w 0)))", "t.rules:1:1:", "rule r: mixes the width placeholder w with width 8"),
    ("(rule r (not ?x) => ?x)\n(rule r (neg ?x) => ?x)", "t.rules:2:1:", "duplicate rule name r")
  ]

syntaxRejected :: [Text]
syntaxRejected =
  [ "(",
    "()",
    "(rule)",
    "(rule r)",
    "(rule r ?x)",
    "(rule r (not ?x) => )",
    "(rule r (not ?x) ?x)",
    "(rule r (not ?x) => ?x",
    "(rule r (not ?x) => ?x))",
    "(rulex r (not ?x) => ?x)",
    "(rule r! (not ?x) => ?x)",
    "(add ?x ?y)",
    -- a bare identifier is not a pattern variable
    "(rule r (not x) => x)",
    "(rule r (not ? x) => ?x)",
    "(rule r (not ?1x) => ?x)",
    "(rule r (not ?x) => ?x :when (ult ?x ?x))",
    "(rule r (not ?x) => ?x :if)",
    "(rule r (not ?x) => ?x :if (ult ?x ?x) :if (ult ?x ?x))",
    -- the placeholder is exactly the word w
    "(rule r (add ?x (const wx 1)) => ?x)",
    "(rule r (add ?x (const W 1)) => ?x)",
    "(rule r (add ?x (const w)) => ?x)",
    -- concrete constants are range-checked as in parseExpr
    "(rule r (add ?x (const 8 256)) => ?x)",
    -- comments only between rules
    "(rule r (add ?x ; no\n (const w 1)) => ?x)",
    "(rule r (not ?x) => ?x) junk"
  ]
