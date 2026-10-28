{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Solver (
  Model,
  SolverResult (..),
  runZ3,
  parseOutput,
)
where

import Control.Exception (IOException, bracket, try)
import Control.Monad (unless, void)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Numeric (readBin, readHex)
import System.Directory (findExecutable)
import System.IO (Handle, hClose, stderr)
import System.IO.Unsafe (unsafePerformIO)
import System.Process (
  CreateProcess (..),
  ProcessHandle,
  StdStream (..),
  cleanupProcess,
  createProcess,
  proc,
  readProcess,
  waitForProcess,
 )
import System.Timeout (timeout)

type Model = Map Text Integer

data SolverResult
  = Sat Model
  | Unsat
  | Unknown Text
  | SolverError Text
  deriving (Eq, Show)

runZ3 :: Int -> Text -> IO SolverResult
runZ3 ms script = do
  found <- findExecutable "z3"
  case found of
    Nothing -> pure (SolverError "z3 not found on PATH; install z3 to use the SMT verifier")
    Just z3 -> do
      printVersionOnce z3
      result <- try @IOException (bracket (createProcess (z3In z3)) release talk)
      pure (either (SolverError . T.pack . show) id result)
  where
    z3In z3 = (proc z3 ["-in", "-smt2"]){std_in = CreatePipe, std_out = CreatePipe}
    talk (Just hIn, Just hOut, _, _) = do
      answer <- timeout (ms * 1000) $ do
        TIO.hPutStr hIn script
        hClose hIn -- z3 sees end of input, answers, and exits
        TIO.hGetContents hOut -- strict: reads until z3 closes stdout
      pure (maybe (Unknown ("timeout after " <> T.pack (show ms) <> " ms")) parseOutput answer)
    talk _ = pure (SolverError "createProcess did not return the stdin and stdout pipes")

release :: (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle) -> IO ()
release p@(_, _, _, ph) = cleanupProcess p >> void (waitForProcess ph)

versionPrinted :: IORef Bool
versionPrinted = unsafePerformIO (newIORef False)
{-# NOINLINE versionPrinted #-}

printVersionOnce :: FilePath -> IO ()
printVersionOnce z3 = do
  printed <- atomicModifyIORef' versionPrinted (True,)
  unless printed $ do
    version <- try @IOException (readProcess z3 ["--version"] "")
    TIO.hPutStrLn stderr $
      either (("z3 --version failed: " <>) . T.pack . show) (T.strip . T.pack) version
        <> " ("
        <> T.pack z3
        <> ")"

parseOutput :: Text -> SolverResult
parseOutput out = case T.lines out of
  "unsat" : _ -> Unsat
  "unknown" : _ -> Unknown "z3 answered unknown"
  "sat" : rest -> either SolverError Sat (parseModel (T.unlines rest))
  _ -> SolverError ("z3 gave no answer: " <> T.strip out)

parseModel :: Text -> Either Text Model
parseModel t = case tokens of
  [] -> Right Map.empty
  "(" : rest -> pairs Map.empty rest
  _ -> bad
  where
    tokens = T.words (T.replace ")" " ) " (T.replace "(" " ( " t))
    pairs m [")"] = Right m
    pairs m ("(" : sym : val : ")" : rest) = do
      v <- value val
      pairs (Map.insert sym v m) rest
    pairs _ _ = bad
    value "true" = Right 1
    value "false" = Right 0
    value v
      | Just h <- T.stripPrefix "#x" v = digits readHex h
      | Just b <- T.stripPrefix "#b" v = digits readBin b
    value _ = bad
    digits rd s = case rd (T.unpack s) of
      [(n, "")] -> Right n
      _ -> bad
    bad = Left ("cannot read the model: " <> T.strip t)
