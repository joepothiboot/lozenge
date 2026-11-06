{-# LANGUAGE OverloadedStrings #-}

module Lozenge.TensorOptSpec (tests) where

import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Lozenge.EGraph (ClassId)
import Lozenge.Fusion (Program (..), fuse, kernelWeight, programCost, totalCost)
import Lozenge.Graph
import Lozenge.Tensor (shapeVal)
import Lozenge.TensorOpt
import TensorPrograms (Prog (..), programs)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "TensorOpt"
    [ testGroup
        "rules"
        [ testCase "the rule list" $
            map ruleName tensorRules @?= ["transpose-transpose", "transpose-matmul", "transpose-add", "factor-left", "factor-right", "reshape-reshape"],
          testGroup
            "transpose-transpose"
            [ testCase "matches" $ apply transposeTranspose tt (Transpose 1) @?= [Class 0],
              testCase "no inner transpose" $ apply transposeTranspose tt (Transpose 0) @?= [],
              testCase "one result per matching node, in order" $
                apply transposeTranspose (IM.fromList [(0, [sq "p"]), (1, [sq "q"]), (2, [Transpose 0, Transpose 1])]) (Transpose 2)
                  @?= [Class 0, Class 1],
              testCase "a missing class matches nothing" $ apply transposeTranspose tt (Transpose 9) @?= [],
              testCase "another operation" $ apply transposeTranspose tt (Add 1 1) @?= []
            ],
          testCase "transpose-matmul" $
            apply transposeMatMul factors (Transpose 3)
              @?= [Node (MatMul (Node (Transpose (Class 1))) (Node (Transpose (Class 0))))],
          testGroup
            "transpose-add"
            [ testCase "matches" $ apply transposeAdd ta (Add 2 3) @?= [Node (Transpose (Node (Add (Class 0) (Class 1))))],
              testCase "one side isn't a transpose" $ apply transposeAdd ta (Add 2 0) @?= []
            ],
          testGroup
            "factor-left"
            [ testCase "shared left operand" $ apply factorLeft factors (Add 3 4) @?= [Node (MatMul (Class 0) (Node (Add (Class 1) (Class 2))))],
              testCase "different left operands" $ apply factorLeft factors (Add 3 6) @?= []
            ],
          testGroup
            "factor-right"
            [ testCase "shared right operand" $ apply factorRight factors (Add 3 6) @?= [Node (MatMul (Node (Add (Class 0) (Class 5))) (Class 1))],
              testCase "different right operands" $ apply factorRight factors (Add 3 4) @?= []
            ],
          testGroup
            "reshape-reshape"
            [ testCase "matches" $ apply reshapeReshape rr (Reshape [6] 1) @?= [Node (Reshape [6] (Class 0))],
              testCase "no inner reshape" $ apply reshapeReshape rr (Reshape [6] 0) @?= []
            ]
        ],
      testGroup
        "localCost"
        [ testCase "input" $ localCost (Input "x" [2, 3]) @?= Costed 0 [2, 3],
          testCase "add is the children plus 1" $ localCost (Add (Costed 5 [2, 3]) (Costed 7 [2, 3])) @?= Costed 13 [2, 3],
          testCase "relu is the child plus 1" $ localCost (Relu (Costed 2 [2, 3])) @?= Costed 3 [2, 3],
          testCase "reshape" $ localCost (Reshape [6] (Costed 3 [2, 3])) @?= Costed 4 [6],
          testCase "matmul" $ localCost (MatMul (Costed 0 [2, 3]) (Costed 0 [3, 4])) @?= Costed (kernelWeight + 6 + 12 + 8) [2, 4],
          testCase "transpose" $ localCost (Transpose (Costed 1 [2, 3])) @?= Costed (1 + kernelWeight + 12) [3, 2],
          testCase "concat" $ localCost (Concat 0 (Costed 0 [2, 3]) (Costed 0 [1, 3])) @?= Costed (kernelWeight + 18) [3, 3],
          testCase "slice" $ localCost (Slice 1 0 2 (Costed 0 [2, 3])) @?= Costed (kernelWeight + 8) [2, 2],
          testCase "ill-shaped node" $ localCost (Add (Costed 0 [2, 3]) (Costed 0 [3, 2])) @?= IllShaped,
          testCase "ill-shaped child" $ localCost (Transpose IllShaped) @?= IllShaped,
          testCase "IllShaped is the most expensive" $ assertBool "Ord" (Costed 5 [] < Costed 6 [] && Costed maxBound [] < IllShaped)
        ],
      testGroup
        "optimise"
        [ testCase "transpose (transpose (x + x')): 3 kernels to 1" $ kernels "transpose (transpose (x + x'))" @?= Just (3, 1),
          testCase "x y + x y': 3 kernels to 2" $ kernels "x y + x y'" @?= Just (3, 2),
          testCase "x y + x' y: 3 kernels to 2" $ kernels "x y + x' y" @?= Just (3, 2),
          testCase "transpose z + transpose z': 3 kernels to 2" $ kernels "transpose z + transpose z'" @?= Just (3, 2),
          testCase "a tie returns the input" $
            let (g, r) = progGraph "reshape (reshape x)"; (g', r') = optimise 8 g r
             in (graphNodes g', r') @?= (graphNodes g, r),
          testCase "an ill-shaped graph comes back unchanged" $
            let g = build [Input "a" [2, 3], Input "b" [3, 2], Add 0 1]; (g', r') = optimise 8 g 2
             in (graphNodes g', r') @?= (graphNodes g, 2),
          testCase "worse once fused: (transpose z + transpose z') * transpose z comes back unchanged" $
            let (g, r) = progGraph "(transpose z + transpose z') * transpose z"; (g', r') = optimise 8 g r
             in (graphNodes g', r') @?= (graphNodes g, r),
          testCase "worse once fused: the tree cost prefers (z + z')^T" $ do
            let input = localCost (Input "z" [4, 2])
                transposed = localCost (Transpose input)
            localCost (Add transposed transposed) @?= Costed (2 * (kernelWeight + 16) + 1) [2, 4]
            localCost (Transpose (localCost (Add input input))) @?= Costed (kernelWeight + 16 + 1) [2, 4],
          testCase "worse once fused: (z + z')^T costs a kernel more" $ do
            let (g, r) = progGraph "(transpose z + transpose z') * transpose z"
                rewritten = build [Input "z" [4, 2], Input "z'" [4, 2], Add 0 1, Transpose 2, Transpose 0, Mul 3 4]
            cost g r @?= Just (3 * kernelWeight + 56)
            cost rewritten 5 @?= Just (4 * kernelWeight + 80)
        ],
      testGroup
        "optimise: same shape, never more expensive"
        [ testCase name $ do
            let (g, r) = lower t
                (g', r') = optimise 8 g r
            (inferShapes g' >>= maybe (Left "no root") Right . IM.lookup r') @?= Right (shapeVal t)
            case (cost g r, cost g' r') of
              (Just before, Just after) -> assertBool ("cost went from " <> show before <> " to " <> show after) (after <= before)
              _ -> assertFailure "fuse returned Left"
        | Prog name t <- programs
        ]
    ]

apply :: TensorRule -> Snapshot -> Op ClassId -> [Rhs]
apply = ruleApply

sq :: Text -> Op ClassId
sq n = Input n [3, 3]

-- x, and transpose x.
tt :: Snapshot
tt = IM.fromList [(0, [Input "x" [2, 3]]), (1, [Transpose 0])]

-- z and z', each transposed.
ta :: Snapshot
ta = IM.fromList [(0, [Input "z" [4, 2]]), (1, [Input "z'" [4, 2]]), (2, [Transpose 0]), (3, [Transpose 1])]

-- x y, x w and x' y.
factors :: Snapshot
factors =
  IM.fromList
    [ (0, [Input "x" [2, 3]]),
      (1, [Input "y" [3, 4]]),
      (2, [Input "w" [3, 4]]),
      (3, [MatMul 0 1]),
      (4, [MatMul 0 2]),
      (5, [Input "x'" [2, 3]]),
      (6, [MatMul 5 1])
    ]

-- x, and x reshaped to [3, 2].
rr :: Snapshot
rr = IM.fromList [(0, [Input "x" [2, 3]]), (1, [Reshape [3, 2] 0])]

build :: [Op NodeId] -> Graph
build = foldl (\g n -> snd (insert n g)) emptyGraph

progGraph :: String -> (Graph, NodeId)
progGraph name = case [lower t | Prog n t <- programs, n == name] of
  p : _ -> p
  [] -> error ("no program " <> name)

-- Kernel count before and after optimising.
kernels :: String -> Maybe (Int, Int)
kernels name =
  let (g, r) = progGraph name
      (g', r') = optimise 8 g r
      count h s = either (const Nothing) (Just . length . progKernels) (fuse h s)
   in (,) <$> count g r <*> count g' r'

cost :: Graph -> NodeId -> Maybe Int
cost g r = either (const Nothing) (Just . totalCost . programCost) (fuse g r)
