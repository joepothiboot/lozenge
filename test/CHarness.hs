-- | Compile generated C with the system C compiler and run it.
module CHarness (ccFlags, compileC, runExe, runProgram) where

import Control.Exception (bracket)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Lozenge.EmitC (emitC)
import Lozenge.Fusion (Program)
import System.Directory (getTemporaryDirectory, removeFile)
import System.Exit (ExitCode (..))
import System.IO (hClose, openTempFile)
import System.Process (readProcessWithExitCode)
import Text.Read (readMaybe)

ccFlags :: [String]
ccFlags = ["-std=c11", "-O1", "-Wall", "-Wextra", "-Werror"]

compileC :: Text -> IO FilePath
compileC src = do
  tmp <- getTemporaryDirectory
  (cPath, h) <- openTempFile tmp "lozenge.c"
  BS.hPut h (TE.encodeUtf8 src) >> hClose h
  let exe = cPath <> ".out"
  (code, _, err) <- readProcessWithExitCode "cc" (ccFlags <> ["-o", exe, cPath]) ""
  removeFile cPath
  unless (code == ExitSuccess) $ fail ("cc rejected the generated C:\n" <> err <> "\n" <> T.unpack src)
  pure exe

runExe :: FilePath -> [[Double]] -> IO [Double]
runExe exe ins = do
  (code, out, err) <- readProcessWithExitCode exe [] (unwords (map show (concat ins)))
  unless (code == ExitSuccess) $ fail ("the compiled program failed (" <> show code <> "): " <> err)
  maybe (fail ("cannot read the program's output: " <> show out)) pure (traverse readMaybe (lines out))

runProgram :: Program -> [[Double]] -> IO [Double]
runProgram p ins = do
  src <- either (fail . T.unpack) pure (emitC p)
  bracket (compileC src) removeFile (`runExe` ins)
