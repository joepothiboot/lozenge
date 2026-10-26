module Z3 (requireZ3) where

import Control.Exception (SomeException, displayException, try)
import Data.Typeable (Typeable)
import System.Directory (findExecutable)
import Test.Tasty (TestName, TestTree)
import Test.Tasty.Providers (IsTest (..), singleTest, testFailed, testPassed)
import Test.Tasty.Runners (Result (..))

newtype Z3Test = Z3Test (IO String)
  deriving (Typeable)

instance IsTest Z3Test where
  run _ (Z3Test action) _ = do
    found <- findExecutable "z3"
    case found of
      Nothing ->
        pure
          (testPassed "z3 not found on PATH; install z3 to run this test")
            { resultShortDescription = "SKIPPED"
            }
      Just _ -> either failed testPassed <$> try action
    where
      failed :: SomeException -> Result
      failed = testFailed . displayException
  testOptions = pure []

requireZ3 :: TestName -> IO String -> TestTree
requireZ3 name = singleTest name . Z3Test
