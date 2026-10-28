{-# LANGUAGE DerivingStrategies #-}

module Lozenge.VerifySmt (
  Config (..),
  VerifyError (..),
  Verify,
  runVerify,
  toAssignment,
  verifySmt,
)
where

import Control.Monad.Except (ExceptT, MonadError)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (MonadReader, ReaderT)
import Data.Text (Text)
import Lozenge.Rule (Rule)
import Lozenge.Solver (Model)
import Lozenge.Typecheck (Context)
import Lozenge.VerifyBrute (Assignment, Verdict)

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
runVerify = error "TODO: runVerify"

toAssignment :: Context -> Model -> Either Text Assignment
toAssignment = error "TODO: toAssignment"

verifySmt :: Rule -> Verify Verdict
verifySmt = error "TODO: verifySmt"
