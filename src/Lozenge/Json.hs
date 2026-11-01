module Lozenge.Json (
  VerifyReport (..),
  RuleReport (..),
  Verdict (..),
  Value (..),
  OptimizeReport (..),
  Refused (..),
  PairsReport (..),
  Pair (..),
  Join (..),
)
where

import Data.Aeson (Options (..), SumEncoding (..), ToJSON (..), camelTo2, defaultOptions, genericToEncoding, genericToJSON)
import Data.Char (isLower, toLower)
import Data.Map.Strict (Map)
import Data.Text (Text)
import GHC.Generics (Generic)

data VerifyReport = VerifyReport
  { vrWidth :: Int,
    vrRules :: [RuleReport]
  }
  deriving (Eq, Show, Generic)

data RuleReport = RuleReport
  { rrName :: Text,
    rrBrute :: Maybe Verdict,
    rrSmt :: Maybe Verdict
  }
  deriving (Eq, Show, Generic)

data Verdict
  = Valid
  | Invalid {vAssignment :: Map Text Value, vLhs :: Value, vRhs :: Value}
  | Unsupported {vReason :: Text}
  deriving (Eq, Show, Generic)

data Value
  = VBV {xWidth :: Int, xValue :: Integer}
  | VBool Bool
  deriving (Eq, Show, Generic)

data OptimizeReport = OptimizeReport
  { orWidth :: Int,
    orInput :: Text,
    orOutput :: Text,
    orInputCost :: Int,
    orOutputCost :: Int,
    orStop :: Text,
    orRefused :: [Refused]
  }
  deriving (Eq, Show, Generic)

data Refused = Refused
  { rfRule :: Text,
    rfReason :: Text
  }
  deriving (Eq, Show, Generic)

data PairsReport = PairsReport
  { psWidth :: Int,
    psPairs :: [Pair]
  }
  deriving (Eq, Show, Generic)

data Pair = Pair
  { pOuter :: Text,
    pInner :: Text,
    pPosition :: [Int],
    pPeak :: Text,
    pLeft :: Text,
    pRight :: Text,
    pJoin :: Join,
    pCheck :: Maybe Verdict
  }
  deriving (Eq, Show, Generic)

data Join
  = Joined {jNormalForm :: Text}
  | NotJoined {jLeft :: Text, jRight :: Text}
  | Unknown
  deriving (Eq, Show, Generic)

options :: SumEncoding -> Options
options sums =
  defaultOptions
    { fieldLabelModifier = lowerFirst . dropWhile isLower,
      constructorTagModifier = camelTo2 '-',
      omitNothingFields = True,
      sumEncoding = sums
    }
  where
    lowerFirst (c : cs) = toLower c : cs
    lowerFirst [] = []

records :: Options
records = options (sumEncoding defaultOptions)

tagged :: String -> Options
tagged tag = options (TaggedObject tag "contents")

instance ToJSON VerifyReport where
  toJSON = genericToJSON records
  toEncoding = genericToEncoding records

instance ToJSON RuleReport where
  toJSON = genericToJSON records
  toEncoding = genericToEncoding records

instance ToJSON Verdict where
  toJSON = genericToJSON (tagged "verdict")
  toEncoding = genericToEncoding (tagged "verdict")

instance ToJSON Value where
  toJSON = genericToJSON (options UntaggedValue)
  toEncoding = genericToEncoding (options UntaggedValue)

instance ToJSON OptimizeReport where
  toJSON = genericToJSON records
  toEncoding = genericToEncoding records

instance ToJSON Refused where
  toJSON = genericToJSON records
  toEncoding = genericToEncoding records

instance ToJSON PairsReport where
  toJSON = genericToJSON records
  toEncoding = genericToEncoding records

instance ToJSON Pair where
  toJSON = genericToJSON records
  toEncoding = genericToEncoding records

instance ToJSON Join where
  toJSON = genericToJSON (tagged "result")
  toEncoding = genericToEncoding (tagged "result")
