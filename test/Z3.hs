module Z3 (requireZ3, requireExe) where

import Control.Exception (SomeException, displayException, try)
import Data.Typeable (Typeable)
import System.Directory (findExecutable)
import Test.Tasty (TestName, TestTree)
import Test.Tasty.Providers (IsTest (..), singleTest, testFailed, testPassed)
import Test.Tasty.Runners (Result (..))

data ExeTest = ExeTest String (IO String)
  deriving (Typeable)

instance IsTest ExeTest where
  run _ (ExeTest exe action) _ = do
    found <- findExecutable exe
    case found of
      Nothing ->
        pure
          (testPassed (exe <> " not found on PATH; install " <> exe <> " to run this test"))
            { resultShortDescription = "SKIPPED"
            }
      Just _ -> either failed testPassed <$> try action
    where
      failed :: SomeException -> Result
      failed = testFailed . displayException
  testOptions = pure []

requireZ3 :: TestName -> IO String -> TestTree
requireZ3 = requireExe "z3"

requireExe :: String -> TestName -> IO String -> TestTree
requireExe exe name = singleTest name . ExeTest exe
