-- Shapes are type-level lists of Nat.
{-# LANGUAGE DataKinds #-}
-- Variable names are Text.
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.TensorSpec (tests) where

import Data.ByteString qualified as BS
import Data.Foldable (for_)
import Data.Map.Strict qualified as M
import Data.Proxy (Proxy (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.TypeLits (natSing)
import Lozenge.Tensor
import Lozenge.TensorEval
import Props (props)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Test.QuickCheck (Gen, Property, arbitrary, forAll, vectorOf, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)

tests :: TestTree
tests =
  testGroup
    "Tensor"
    [ testGroup
        "shapeVal"
        [ testCase "'[]" $ shapeVal (Proxy @'[]) @?= [],
          testCase "'[0]" $ shapeVal (Proxy @'[0]) @?= [0],
          testCase "'[2, 3, 4]" $ shapeVal (Proxy @'[2, 3, 4]) @?= [2, 3, 4],
          testCase "a tensor is a proxy" $ shapeVal a @?= [2, 3]
        ],
      testGroup
        "eval"
        [ testGroup
            "var"
            [ testCase "a" $ a ==> [1, 2, 3, 4, 5, 6],
              testCase "unbound" $ (Var "nope" :: Tensor '[2]) ==! Unbound "nope",
              testCase "wrong length" $ (Var "a" :: Tensor '[4]) ==! WrongLength "a" 4 6,
              testCase "leftmost error wins" $ Add (Var "p") (Var "q" :: Tensor '[1]) ==! Unbound "p"
            ],
          testGroup
            "add and mul"
            [ testCase "add" $ Add a b ==> [11, 22, 33, 44, 55, 66],
              testCase "mul" $ Mul a b ==> [10, 40, 90, 160, 250, 360],
              testCase "a + a * a" $ Add a (Mul a a) ==> [2, 6, 12, 20, 30, 42],
              testCase "error inside" $ Add a (Var "zz") ==! Unbound "zz"
            ],
          testGroup
            "reshape"
            [ testCase "[2,3] to [3,2]" $ Reshape @'[3, 2] a ==> [1, 2, 3, 4, 5, 6],
              testCase "[2,3] to [6]" $ Reshape @'[6] a ==> [1, 2, 3, 4, 5, 6],
              testCase "[1,1] to scalar" $ Reshape @'[] s ==> [42]
            ],
          testGroup
            "transpose"
            [ testCase "[2,3]" $ Transpose a ==> [1, 4, 2, 5, 3, 6],
              testCase "[3,2]" $ Transpose c ==> [1, 0, 1, 0, 1, 1],
              testCase "[1,3] is the same list" $ Transpose (Reshape @'[1, 3] v) ==> [7, 8, 9],
              testCase "twice" $ Transpose (Transpose a) ==> [1, 2, 3, 4, 5, 6]
            ],
          testGroup
            "matmul"
            [ testCase "[2,2] [2,2]" $ MatMul m n ==> [19, 22, 43, 50],
              testCase "[2,3] [3,2]" $ MatMul a c ==> [4, 5, 10, 11],
              testCase "[3,2] [2,3]" $ MatMul c a ==> [1, 2, 3, 4, 5, 6, 5, 7, 9],
              testCase "dot product [1,3] [3,1]" $ MatMul (Reshape @'[1, 3] v) (Reshape @'[3, 1] v) ==> [194],
              testCase "outer product [3,1] [1,3]" $
                MatMul (Reshape @'[3, 1] v) (Reshape @'[1, 3] v) ==> [49, 56, 63, 56, 64, 72, 63, 72, 81],
              testCase "error inside" $ MatMul (Var "zz" :: Tensor '[1, 2]) m ==! Unbound "zz"
            ],
          testGroup
            "concat"
            [ testCase "axis 0 of [3] [3]" $ (Concat (natSing @0) v v :: Tensor '[6]) ==> [7, 8, 9, 7, 8, 9],
              testCase "axis 0 of [2,3] [2,3]" $
                (Concat (natSing @0) a b :: Tensor '[4, 3]) ==> [1, 2, 3, 4, 5, 6, 10, 20, 30, 40, 50, 60],
              testCase "axis 1 of [2,3] [2,3]" $
                (Concat (natSing @1) a b :: Tensor '[2, 6]) ==> [1, 2, 3, 10, 20, 30, 4, 5, 6, 40, 50, 60],
              testCase "axis 1 of [2,3] [2,2]" $
                (Concat (natSing @1) a m :: Tensor '[2, 5]) ==> [1, 2, 3, 1, 2, 4, 5, 6, 3, 4],
              testCase "axis 1 of [2,2,3] [2,2,3]" $
                (Concat (natSing @1) t t :: Tensor '[2, 4, 3]) ==> [1 .. 6] <> [1 .. 6] <> [7 .. 12] <> [7 .. 12],
              testCase "axis 2 of [2,2,3] [2,2,3]" $
                (Concat (natSing @2) t t :: Tensor '[2, 2, 6])
                  ==> concatMap (\r -> r <> r) [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11, 12]],
              testCase "axis 0 of [2,2,3] [2,2,3]" $
                (Concat (natSing @0) t t :: Tensor '[4, 2, 3]) ==> [1 .. 12] <> [1 .. 12],
              testCase "axis 0 of [2,2,3] [1,2,3], slice from start 1" $
                (Concat (natSing @0) t (Slice (natSing @0) (natSing @1) (natSing @1) t) :: Tensor '[3, 2, 3])
                  ==> [1 .. 12]
                  <> [7 .. 12]
            ],
          testGroup
            "slice"
            [ testCase "axis 0 of [2,3], row 1" $
                (Slice (natSing @0) (natSing @1) (natSing @1) a :: Tensor '[1, 3]) ==> [4, 5, 6],
              testCase "axis 1 of [2,3], columns 1..2" $
                (Slice (natSing @1) (natSing @1) (natSing @2) a :: Tensor '[2, 2]) ==> [2, 3, 5, 6],
              testCase "axis 1 of [2,3], length 0" $
                (Slice (natSing @1) (natSing @3) (natSing @0) a :: Tensor '[2, 0]) ==> [],
              testCase "all of axis 0 is the identity" $
                (Slice (natSing @0) (natSing @0) (natSing @2) a :: Tensor '[2, 3]) ==> [1, 2, 3, 4, 5, 6],
              testCase "axis 1 of [2,2,3], row 1" $
                (Slice (natSing @1) (natSing @1) (natSing @1) t :: Tensor '[2, 1, 3]) ==> [4, 5, 6, 10, 11, 12],
              testCase "axis 2 of [2,2,3], column 2" $
                (Slice (natSing @2) (natSing @2) (natSing @1) t :: Tensor '[2, 2, 1]) ==> [3, 6, 9, 12],
              testCase "axis 0 of [3,2,2], start 1 length 2" $
                (Slice (natSing @0) (natSing @1) (natSing @2) (Reshape @'[3, 2, 2] t) :: Tensor '[2, 2, 2]) ==> [5 .. 12],
              testCase "axis 0 of [3,2,2], start 2 length 1" $
                (Slice (natSing @0) (natSing @2) (natSing @1) (Reshape @'[3, 2, 2] t) :: Tensor '[1, 2, 2]) ==> [9 .. 12]
            ]
        ],
      props $
        testGroup
          "laws"
          [ testProperty "transpose (transpose x) = x" $ Transpose (Transpose x) =~= x,
            testProperty "(x y)^T = y^T x^T" $ Transpose (MatMul x y) =~= MatMul (Transpose y) (Transpose x),
            testProperty "matmul is associative" $ MatMul (MatMul x y) z =~= MatMul x (MatMul y z),
            testProperty "matmul distributes over add" $ MatMul x (Add y y') =~= Add (MatMul x y) (MatMul x y'),
            testProperty "add commutes" $ Add x x' =~= Add x' x,
            testProperty "mul commutes" $ Mul x x' =~= Mul x' x,
            testProperty "reshape and back" $ Reshape @'[2, 3] (Reshape @'[3, 2] x) =~= x,
            testProperty "slice undoes concat, axis 0" $
              Slice (natSing @0) (natSing @2) (natSing @2) (Concat (natSing @0) x x') =~= x',
            testProperty "slice undoes concat, axis 1" $
              Slice (natSing @1) (natSing @0) (natSing @4) (Concat (natSing @1) y y') =~= y,
            testProperty "slice undoes concat, axis 0 of 3-D, start 3" $
              Slice (natSing @0) (natSing @3) (natSing @3) (Concat (natSing @0) (Reshape @'[3, 2, 2] y) (Reshape @'[3, 2, 2] y'))
                =~= Reshape @'[3, 2, 2] y',
            testProperty "concat of two slices is the whole" $
              Concat (natSing @1) (Slice (natSing @1) (natSing @0) (natSing @1) x) (Slice (natSing @1) (natSing @1) (natSing @2) x)
                =~= x,
            testProperty "length is the product of the shape" $
              let wide = Concat (natSing @1) (MatMul x y) (Transpose z) :: Tensor '[2, 8]
                  prog = Slice (natSing @1) (natSing @3) (natSing @4) wide
               in forAll genInputs $ \env -> (length <$> evalTensor env prog) === Right (product (shapeVal prog)),
            testProperty "Integer and Double agree" $
              let prog = Add (MatMul (Add x x') y) (Transpose (Mul z z))
               in forAll genInputs $ \env ->
                    (map fromInteger <$> evalTensor env prog)
                      === (evalTensor (map fromInteger <$> env) prog :: Either InputError [Double])
          ],
      testGroup
        "shape errors do not compile"
        ( map
            shouldNotCompile
            [ "AddShape.hs",
              "MatMulInner.hs",
              "TransposeRank.hs",
              "ReshapeProduct.hs",
              "ConcatOffAxis.hs",
              "ConcatAxisRange.hs",
              "ConcatResult.hs",
              "SliceBounds.hs",
              "SliceAxisRange.hs"
            ]
        )
    ]

-- Unit tests: one fixed set of inputs, evaluated at Integer and at Double.

inputs :: Inputs Integer
inputs =
  M.fromList
    [ ("a", [1 .. 6]),
      ("b", [10, 20 .. 60]),
      ("c", [1, 0, 0, 1, 1, 1]),
      ("m", [1, 2, 3, 4]),
      ("n", [5, 6, 7, 8]),
      ("s", [42]),
      ("t", [1 .. 12]),
      ("v", [7, 8, 9])
    ]

a, b :: Tensor '[2, 3]
a = Var "a"
b = Var "b"

c :: Tensor '[3, 2]
c = Var "c"

m, n :: Tensor '[2, 2]
m = Var "m"
n = Var "n"

s :: Tensor '[1, 1]
s = Var "s"

t :: Tensor '[2, 2, 3]
t = Var "t"

v :: Tensor '[3]
v = Var "v"

-- | Evaluates to @expected@ at Integer and, converted, at Double.
(==>) :: Tensor sh -> [Integer] -> Assertion
x0 ==> expected = do
  evalTensor inputs x0 @?= Right expected
  evalTensor (map fromInteger <$> inputs) x0 @?= Right (map fromInteger expected :: [Double])

infix 1 ==>

-- | Fails with this input error.
(==!) :: Tensor sh -> InputError -> Assertion
x0 ==! err = evalTensor inputs x0 @?= (Left err :: Either InputError [Integer])

infix 1 ==!

-- Properties: random Integer inputs, so every law holds exactly.

x, x' :: Tensor '[2, 3]
x = Var "x"
x' = Var "x'"

y, y' :: Tensor '[3, 4]
y = Var "y"
y' = Var "y'"

z :: Tensor '[4, 2]
z = Var "z"

genInputs :: Gen (Inputs Integer)
genInputs =
  M.fromList
    <$> traverse
      (\(name, len) -> (name,) <$> vectorOf len arbitrary)
      [("x", 6), ("x'", 6), ("y", 12), ("y'", 12), ("z", 8)]

-- | Both sides evaluate to the same result on random inputs.
(=~=) :: Tensor sh -> Tensor sh -> Property
lhs =~= rhs = forAll genInputs $ \env -> evalTensor env lhs === evalTensor env rhs

infix 1 =~=

-- | Each file in test/should-fail/ is a program with one shape error. GHC
-- must reject it, and its message must contain every @-- expect:@ line in the
-- file. Without that check a typo, or any unrelated error, would also pass.
--
-- Quote characters are dropped from both sides, because GHC prints ‘x’ in a
-- UTF-8 locale and 'x' otherwise. Needs @ghc@ on PATH; @stack test@ provides it.
shouldNotCompile :: FilePath -> TestTree
shouldNotCompile file = testCase file $ do
  src <- TE.decodeUtf8 <$> BS.readFile path
  let expected = [e | l <- T.lines src, Just e <- [T.stripPrefix "-- expect: " l]]
  (code, _, err) <- readProcessWithExitCode "ghc" ["-fno-code", "-package-env", "-", "-isrc", path] ""
  assertBool "ghc accepted a program with a shape error" (code /= ExitSuccess)
  assertBool "the file has no -- expect: line" (not (null expected))
  for_ expected $ \e ->
    assertBool
      ("ghc's message does not contain: " <> T.unpack e <> "\n" <> err)
      (unquote e `T.isInfixOf` unquote (T.pack err))
  where
    path = "test/should-fail/" <> file
    unquote = T.filter (`notElem` ("‘’'`" :: String))
