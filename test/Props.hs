module Props (props) where

import Test.Tasty (TestTree, adjustOption)
import Test.Tasty.QuickCheck (QuickCheckTests (..))

props :: TestTree -> TestTree
props = adjustOption (\(QuickCheckTests n) -> QuickCheckTests (max 200 n))
