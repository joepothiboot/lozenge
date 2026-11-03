{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.GradSpec (tests) where

import Data.Either (fromRight)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import GHC.TypeLits (natSing)
import Lozenge.Grad (grad)
import Lozenge.Mlp (squaredErrors)
import Lozenge.Tensor
import Lozenge.TensorEval
import Props (props)
import TensorPrograms (Prog (..), inputSizes, programs)
import Test.QuickCheck (Gen, Property, choose, conjoin, counterexample, forAll, vectorOf, (===))
import Test.QuickCheck qualified as QC
import Test.Tasty (TestTree, localOption, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (QuickCheckTests (..), testProperty)

tests :: TestTree
tests =
  testGroup
    "Grad"
    [ testGroup
        "unit"
        [ testCase "an input is all ones" $ a ==> [("a", [1, 1, 1, 1, 1, 1])],
          testCase "a + a: one entry, twice the gradient" $ Add a a ==> [("a", [2, 2, 2, 2, 2, 2])],
          testCase "add" $ Add a b ==> [("a", ones 6), ("b", ones 6)],
          testCase "mul swaps the operands" $ Mul a b ==> [("a", [10, 20 .. 60]), ("b", [1 .. 6])],
          testCase "a * a is 2a" $ Mul a a ==> [("a", [2, 4 .. 12])],
          testCase "matmul" $ MatMul m n ==> [("m", [11, 15, 11, 15]), ("n", [4, 4, 6, 6])],
          testCase "matmul, weighted" $
            Mul (MatMul m n) w22 ==> [("m", [65, 87, 6500, 8700]), ("n", [301, 3010, 402, 4020]), ("w22", [19, 22, 43, 50])],
          testCase "transpose, weighted" $ Mul (Transpose a) w32 ==> [("a", [1, 3, 5, 2, 4, 6]), ("w32", [1, 4, 2, 5, 3, 6])],
          testCase "reshape, weighted" $ Mul (Reshape @'[3, 2] a) w32 ==> [("a", [1 .. 6]), ("w32", [1 .. 6])],
          testCase "concat along axis 1, weighted" $
            Mul (Concat (natSing @1) a m) w25 ==> [("a", [1, 2, 3, 6, 7, 8]), ("m", [4, 5, 9, 10]), ("w25", [1, 2, 3, 1, 2, 4, 5, 6, 3, 4])],
          testCase "concat along axis 0" $ (Concat (natSing @0) a b :: Tensor '[4, 3]) ==> [("a", ones 6), ("b", ones 6)],
          testCase "slice: zero outside the slice" $
            (Slice (natSing @1) (natSing @1) (natSing @2) a :: Tensor '[2, 2]) ==> [("a", [0, 1, 1, 0, 1, 1])],
          testCase "slice, weighted" $
            Mul (Slice (natSing @1) (natSing @1) (natSing @2) a) m ==> [("a", [0, 1, 2, 0, 3, 4]), ("m", [2, 3, 5, 6])],
          testCase "relu: 0 at and below 0" $ Relu r ==> [("r", [0, 0, 1])],
          testCase "relu, weighted" $ Mul (Relu r) v ==> [("r", [0, 0, 9]), ("v", [0, 0, 3])],
          testCase "one name at two shapes adds up" $
            Add (Reshape @'[2, 3] (Var "a" :: Tensor '[6])) a ==> [("a", [2, 2, 2, 2, 2, 2])],
          testCase "unbound" $ grad inputs (Add a (Var "zz")) @?= Left (Unbound "zz"),
          testCase "wrong length" $ grad inputs (Var "a" :: Tensor '[4]) @?= Left (WrongLength "a" 4 6),
          testCase "leftmost error wins" $ grad inputs (Add (Var "p") (Var "q" :: Tensor '[1])) @?= Left (Unbound "p")
        ],
      props $
        testGroup
          "laws at Integer"
          [ testProperty "keys are the names the program reads" $ forPrograms $ \p env ->
              (M.keys <$> grad env p) === Right (S.toList (S.fromList (vars p))),
            testProperty "each gradient has its input's length" $ forPrograms $ \p env ->
              (M.map length <$> grad env p) === Right (M.map length (M.restrictKeys env (S.fromList (vars p)))),
            testProperty "grad (p + q) = grad p + grad q" $ forAll genIntegers $ \env ->
              let p = MatMul x y
                  q = MatMul x' (Add y y')
               in grad env (Add p q) === (M.unionWith (zipWith (+)) <$> grad env p <*> grad env q),
            testProperty "grad (3 p) = 3 grad p" $ forAll genIntegers $ \env ->
              let p = Relu (Mul x x')
               in grad env (Add p (Add p p)) === (M.map (map (* 3)) <$> grad env p),
            testProperty "Integer and Double agree" $ forAll genIntegers $ \env ->
              let p = Mul (Relu (Add (MatMul x y) (MatMul x' y'))) (MatMul x y)
               in (M.map (map fromInteger) <$> grad env p) === (grad (map fromInteger <$> env) p :: Either InputError (M.Map Text [Double]))
          ],
      localOption (QuickCheckTests 100) $
        testGroup
          "same as central finite differences (Double)"
          ( [finiteDifferences inputSizes prog | prog <- programs]
              <> [ finiteDifferences
                     [("x", 8), ("ones", 4), ("minus y", 4), ("w1", 6), ("b1", 3), ("w2", 3), ("b2", 1)]
                     (Prog "MLP squared errors, n = 4, h = 3" (squaredErrors @4 @3))
                 ]
          )
    ]

inputs :: Inputs Integer
inputs =
  M.fromList
    [ ("a", [1 .. 6]),
      ("b", [10, 20 .. 60]),
      ("m", [1, 2, 3, 4]),
      ("n", [5, 6, 7, 8]),
      ("r", [-2, 0, 3]),
      ("v", [7, 8, 9]),
      ("w22", [1, 10, 100, 1000]),
      ("w32", [1 .. 6]),
      ("w25", [1 .. 10])
    ]

a, b :: Tensor '[2, 3]
a = Var "a"
b = Var "b"

m, n, w22 :: Tensor '[2, 2]
m = Var "m"
n = Var "n"
w22 = Var "w22"

w32 :: Tensor '[3, 2]
w32 = Var "w32"

w25 :: Tensor '[2, 5]
w25 = Var "w25"

r, v :: Tensor '[3]
r = Var "r"
v = Var "v"

ones :: Int -> [Integer]
ones k = replicate k 1

(==>) :: Tensor s -> [(Text, [Integer])] -> IO ()
p ==> expected = grad inputs p @?= Right (M.fromList expected)

infix 1 ==>

x, x' :: Tensor '[2, 3]
x = Var "x"
x' = Var "x'"

y, y' :: Tensor '[3, 4]
y = Var "y"
y' = Var "y'"

genIntegers :: Gen (Inputs Integer)
genIntegers = genWith (choose (-5, 5)) inputSizes

forPrograms :: (forall s. Tensor s -> Inputs Integer -> Property) -> Property
forPrograms law = conjoin [counterexample name (forAll genIntegers (law p)) | Prog name p <- programs]

finiteDifferences :: [(Text, Int)] -> Prog -> TestTree
finiteDifferences sizes (Prog name p) =
  testProperty name $ forAll (genWith (choose (-2, 2)) (("seed", product (shapeVal p)) : sizes)) $ \env ->
    let q = Mul p (Var "seed")
        f e = either (const 0) sum (evalTensor e q)
        central k i = (f (bump k i h) - f (bump k i (-h))) / (2 * h)
        bump k i d = M.adjust (\xs -> [if j == i then e + d else e | (j, e) <- zip [0 :: Int ..] xs]) k env
        close k i g =
          let fd = central k i
           in counterexample (T.unpack k <> "[" <> show i <> "]: grad " <> show g <> ", finite difference " <> show fd) $
                abs (fd - g) <= 1e-4 * (1 + abs g)
     in all ((> 1e-2) . abs) (reluInputs env q)
          QC.==> case grad env q of
            Left err -> counterexample (show err) False
            Right gs -> conjoin [close k i g | (k, g_k) <- M.toList gs, (i, g) <- zip [0 ..] g_k]
  where
    h = 1e-4

genWith :: Gen a -> [(Text, Int)] -> Gen (Inputs a)
genWith gen sizes = M.fromList <$> traverse (\(k, len) -> (k,) <$> vectorOf len gen) sizes

vars :: Tensor s -> [Text]
vars = walk (\case Var k -> [k]; _ -> [])

reluInputs :: Inputs Double -> Tensor s -> [Double]
reluInputs env = walk (\case Relu e -> fromRight [] (evalTensor env e); _ -> [])

walk :: (Monoid w) => (forall t. Tensor t -> w) -> Tensor s -> w
walk f t =
  f t <> case t of
    Var _ -> mempty
    Add p q -> walk f p <> walk f q
    Mul p q -> walk f p <> walk f q
    Relu p -> walk f p
    MatMul p q -> walk f p <> walk f q
    Transpose p -> walk f p
    Reshape p -> walk f p
    Concat _ p q -> walk f p <> walk f q
    Slice _ _ _ p -> walk f p
