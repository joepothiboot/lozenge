module Main (main) where

import Data.List (intercalate)
import Data.Text.IO qualified as TIO
import Lozenge.Cli (Command (..), Cost (..), Engine (..), Solver (..), run)
import Options.Applicative
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)
import Text.Read (readMaybe)

main :: IO ()
main = do
  (json, cmd) <- execParser (info (commands <**> helper) (failureCode 2 <> progDesc "Verify bitvector rewrite rules and optimise with them"))
  result <- run json cmd
  case result of
    Left err -> TIO.hPutStrLn stderr err >> exitWith (ExitFailure 2)
    Right (code, out) -> TIO.putStr out >> exitWith code

commands :: Parser (Bool, Command)
commands =
  hsubparser $
    command "verify" (info (withJson (Verify <$> rulesArg <*> width <*> solver)) (failureCode 2 <> progDesc "Check every rule; exit 1 if any has a counterexample"))
      <> command "optimize" (info (withJson (Optimize <$> exprArg <*> rulesOpt <*> width <*> cost <*> engine)) (failureCode 2 <> progDesc "Rewrite an expression with the rules that verify at the width"))
      <> command "critical-pairs" (info (withJson (CriticalPairs <$> rulesArg <*> width)) (failureCode 2 <> progDesc "List the rules' critical pairs and check the ones that don't join with z3"))
  where
    withJson p = flip (,) <$> p <*> switch (long "json" <> help "Print JSON (schema: docs/JSON.md)")
    rulesArg = strArgument (metavar "RULES.rules")
    exprArg = strArgument (metavar "EXPR.ir")
    rulesOpt = strOption (long "rules" <> metavar "RULES.rules")
    width = option (eitherReader readWidth) (long "width" <> metavar "N" <> value 8 <> help "Bitvector width, 1 to 64 (default: 8)")
    solver = option (choice [("brute", Brute), ("smt", Smt), ("both", Both)]) (long "solver" <> metavar "brute|smt|both" <> value Brute <> help "default: brute")
    cost = option (choice [("size", Size), ("shifts", Shifts)]) (long "cost" <> metavar "size|shifts" <> value Size <> help "default: size")
    engine = option (choice [("greedy", Greedy), ("egraph", EGraph)]) (long "engine" <> metavar "greedy|egraph" <> value EGraph <> help "default: egraph")

readWidth :: String -> Either String Int
readWidth s = case readMaybe s of
  Just n | n >= 1 && n <= 64 -> Right n
  _ -> Left ("expected a width from 1 to 64, got " <> s)

choice :: [(String, a)] -> ReadM a
choice table = eitherReader (\s -> maybe (Left ("expected one of " <> names)) Right (lookup s table))
  where
    names = intercalate ", " (map fst table)
