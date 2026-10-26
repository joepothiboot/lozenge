module Golden (goldenText) where

import Control.Exception (evaluate)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Test.Tasty (TestName, TestTree)
import Test.Tasty.Golden (goldenVsString)

goldenText :: TestName -> FilePath -> IO Text -> TestTree
goldenText name file action =
  goldenVsString name ("test/golden/" <> file) (LBS.fromStrict . TE.encodeUtf8 <$> (action >>= evaluate))
