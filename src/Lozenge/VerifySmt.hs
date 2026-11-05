{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Lozenge.VerifySmt (
  Config (..),
  VerifyError (..),
  Verify,
  runVerify,
  toAssignment,
  verifySmt,
)
where

import Control.Monad.Except (ExceptT, MonadError, liftEither, runExceptT, throwError)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, asks, runReaderT)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Lozenge.EvalT (checkEnv)
import Lozenge.Expr (Value (..), validValue)
import Lozenge.Rule (Rule (..), instantiate)
import Lozenge.Smt (ruleQuery, smtName)
import Lozenge.Solver (Model, SolverResult (..), runZ3)
import Lozenge.Typecheck (Context, typecheck)
import Lozenge.Typed (Ty (..))
import Lozenge.VerifyBrute (Assignment, Verdict (..), evalSome)

data Config = Config
  { configWidth :: Int,
    configTimeoutMs :: Int
  }
  deriving (Eq, Show)

data VerifyError
  = SolverFailed Text
  | SpuriousCounterexample Assignment
  deriving (Eq, Show)

newtype Verify a = Verify (ReaderT Config (ExceptT VerifyError IO) a)
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadReader Config, MonadError VerifyError)

runVerify :: Config -> Verify a -> IO (Either VerifyError a)
runVerify config (Verify action) = runExceptT (runReaderT action config)

toAssignment :: Context -> Model -> Either Text Assignment
toAssignment ctx model = Map.traverseWithKey value ctx
  where
    value x ty = do
      let name = smtName x
      n <- maybe (Left (name <> " is missing from the model")) Right (Map.lookup name model)
      case ty of
        TBool
          | n == 0 -> Right (VBool False)
          | n == 1 -> Right (VBool True)
          | otherwise -> Left (name <> " is Bool, but the model gives " <> showT n)
        TBV w
          | validValue v -> Right v
          | otherwise -> Left (name <> " is BV " <> showT w <> ", but the model gives " <> showT n)
          where
            v = VBV (fromIntegral w) n

verifySmt :: Rule -> Verify Verdict
verifySmt rule = do
  w <- asks configWidth
  ms <- asks configTimeoutMs
  case prepare w of
    Left verdict -> pure verdict
    Right (r, query) -> do
      result <- liftIO (runZ3 ms query)
      case result of
        Unsat -> pure Valid
        Unknown msg -> pure (Unsupported msg)
        SolverError msg -> throwError (SolverFailed msg)
        Sat model -> do
          a <- liftEither (first SolverFailed (toAssignment (ruleVars r) model))
          liftEither (confirm r a)
  where
    prepare w = do
      r <- maybe (Left (Unsupported ("width " <> showT w <> " is outside 1..64"))) Right (instantiate w rule)
      query <- first Unsupported (ruleQuery r)
      pure (r, query)

confirm :: Rule -> Assignment -> Either VerifyError Verdict
confirm r a = do
  (holds, l, e) <- first (const spurious) sides
  if holds && l /= e then Right (Counterexample a l e) else Left spurious
  where
    spurious = SpuriousCounterexample a
    sides = do
      tenv <- checkEnv (ruleVars r) a
      let value t = evalSome tenv <$> typecheck (ruleVars r) t
      pre <- traverse value (rulePre r)
      (all (== VBool True) pre,,) <$> value (ruleLhs r) <*> value (ruleRhs r)

showT :: (Show a) => a -> Text
showT = T.pack . show
