{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.MlpSpec (tests) where

import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Golden (goldenText)
import Lozenge.Mlp
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Mlp"
    [ testGroup
        "data and initialisation"
        [ testCase "uniforms 1 (numpy)" $ take 3 (uniforms 1) @?= [0.42320917087271326, 0.5094074428837206, 0.6483593939634306],
          testCase "uniforms are in [0, 1)" $ assertBool "range" (all (\u -> u >= 0 && u < 1) (take 10000 (uniforms 42))),
          testCase "xor" $ (length (dsPoints xor), dsTargets xor) @?= (8, [0, 1, 1, 0]),
          testCase "moons: 200 points, half of each class" $
            let ds = moons 200 7
             in (length (dsPoints ds), dsTargets ds) @?= (400, replicate 100 0 <> replicate 100 1),
          testCase "moons 200 7: points 0 and 150 (numpy)" $
            let ps = dsPoints (moons 200 7)
             in [p | (i, p) <- zip [0 :: Int ..] ps, i `elem` [0, 1, 300]] @?= [0.11245458423375629, 1.081087810285891, 1.9897813858462734],
          testCase "moons: a seed is deterministic, another seed differs" $
            assertBool "seeds" (moons 50 3 == moons 50 3 && moons 50 3 /= moons 50 4),
          testCase "initParams: names and lengths" $
            M.map length (initParams @8 1) @?= M.fromList [("w1", 16), ("b1", 8), ("w2", 8), ("b2", 1)],
          testCase "initParams @8 1: first weights (numpy)" $
            (take 1 <$> M.lookup "w1" (initParams @8 1), take 1 <$> M.lookup "w2" (initParams @8 1))
              @?= (Just [-0.26601123520760134], Just [-0.1307068592964881]),
          testCase "initParams: biases and bounds" $ do
            let ps = initParams @8 1
            M.lookup "b1" ps @?= Just (replicate 8 0.1)
            M.lookup "b2" ps @?= Just [0]
            assertBool "w1 within sqrt 3" (all ((<= sqrt 3) . abs) (M.findWithDefault [] "w1" ps))
            assertBool "w2 within sqrt (6 / 8)" (all ((<= sqrt (6 / 8)) . abs) (M.findWithDefault [] "w2" ps))
        ],
      testGroup
        "sgdStep"
        [ testCase "steps parameters with a gradient, keeps the rest" $
            sgdStep 0.5 (M.fromList [("w", [1, 2]), ("k", [3])]) (M.fromList [("w", [2, 2]), ("x", [9])])
              @?= M.fromList [("w", [0, 1]), ("k", [3])]
        ],
      testGroup
        "output"
        [ testCase "lossCsv" $ lossCsv [0.25, 1.0e-3] @?= "epoch,loss\n0,0.25\n1,1.0e-3\n",
          testCase "lossCsv of nothing is the header" $ lossCsv [] @?= "epoch,loss\n",
          goldenText "lossSvg" "mlp-loss.svg" (pure (lossSvg "a <test> & curve" [1, 0.5, 0.1, 3.0e-2, 1.0e-2, 1.0e-3])),
          testCase "lossSvg draws NaN, Infinity, 0 and nothing" $
            mapM_
              (\ls -> assertBool (show ls) (not (any (`T.isInfixOf` lossSvg "t" ls) ["NaN", "Infinity"])))
              [[0 / 0, 1 / 0, 0, 1], [0], []]
        ],
      testGroup
        "training"
        [ testCase "XOR, initial loss (numpy)" $
            initialLoss (train @4 @8 0.1 0 xor (initParams @8 1)) 0.5875281823871774,
          testCase "two moons, initial loss (numpy)" $
            initialLoss (train @200 @16 0.1 0 (moons 200 7) (initParams @16 2)) 0.7744721988957316,
          testCase "XOR: 500 steps fit all four points" $
            case train @4 @8 0.1 500 xor (initParams @8 1) of
              Left err -> assertFailure (show err)
              Right (losses, ps) -> do
                length losses @?= 501
                assertBool ("final loss " <> show (drop 500 losses)) (all (< 1e-6) (drop 500 losses))
                accuracy @4 @8 xor ps @?= Right 1
        ]
    ]

initialLoss :: (Show e) => Either e ([Double], Params) -> Double -> Assertion
initialLoss result expected = case result of
  Right ([l], _) -> assertBool (show l <> " /= " <> show expected) (abs (l - expected) <= 1e-12)
  other -> assertFailure (show (fst <$> other))
