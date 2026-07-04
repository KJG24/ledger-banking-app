{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Core domain types for the banking demo.
--
-- The guiding rule of this module: money is never represented as a
-- floating point number. Every amount is stored as an integer count of
-- the currency's smallest unit (e.g. cents for USD, or whole units for
-- JPY, which has no minor unit). This avoids the classic class of bugs
-- where 19.99 + 0.01 does not quite equal 20.00.
module Banking.Types
  ( -- * Currency
    Currency (..)
  , parseCurrency
  , renderCurrency
  , minorUnitDigits

    -- * Money
  , Money
  , mkMoney
  , moneyMinorUnits
  , moneyCurrency
  , formatMoney

    -- * Transaction type
  , TransactionType (..)
  , parseTransactionType
  , renderTransactionType

    -- * Account identifiers
  , AccountId
  , mkAccountId
  , unAccountId

    -- * Wire types
  , TransactionRequest (..)
  , TransactionStatus (..)
  , RiskFlag (..)
  , renderRiskFlag
  , TransactionResponse (..)
  ) where

import Data.Aeson
import Data.Char (isAlphaNum, isDigit, isSpace, isUpper)
import Data.List (intercalate)
import Data.Scientific (Scientific, toBoundedInteger)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import GHC.Generics (Generic)

--------------------------------------------------------------------------------
-- Currency
--------------------------------------------------------------------------------

-- | The currencies this demo understands. A real core-banking system would
-- load ISO 4217 from a table; a closed set is enough to demonstrate the
-- pattern without pulling in a dependency just for this exercise.
data Currency = USD | EUR | GBP | JPY
  deriving (Eq, Ord, Show, Enum, Bounded)

parseCurrency :: Text -> Either Text Currency
parseCurrency raw = case T.toUpper (T.strip raw) of
  "USD" -> Right USD
  "EUR" -> Right EUR
  "GBP" -> Right GBP
  "JPY" -> Right JPY
  other ->
    Left $
      "unsupported currency \"" <> other
        <> "\" (supported: USD, EUR, GBP, JPY)"

renderCurrency :: Currency -> Text
renderCurrency = T.pack . show

-- | How many decimal places this currency's minor unit has.
-- Yen has no minor unit; the rest of our supported set use cents/pence.
minorUnitDigits :: Currency -> Int
minorUnitDigits JPY = 0
minorUnitDigits _ = 2

currencySymbol :: Currency -> Text
currencySymbol USD = "$"
currencySymbol EUR = "€"
currencySymbol GBP = "£"
currencySymbol JPY = "¥"

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

-- | An amount of money in the smallest unit of its currency (e.g. cents).
-- The constructor is not exported, so the only way to build a 'Money' is
-- through 'mkMoney', which enforces "positive amount, correct precision
-- for the currency" at the boundary.
data Money = Money
  { moneyMinorUnits :: Integer
  , moneyCurrency :: Currency
  }
  deriving (Eq, Show)

-- | Build a 'Money' value from a decimal amount expressed in major units
-- (e.g. @12.50@ meaning twelve dollars fifty), as it would arrive from a
-- JSON request body. Rejects zero/negative amounts and amounts with more
-- decimal places than the currency supports (e.g. fractional yen, or
-- fractional cents).
mkMoney :: Scientific -> Currency -> Either Text Money
mkMoney amount currency
  | amount <= 0 =
      Left "amount must be a positive number"
  | otherwise =
      let digits = minorUnitDigits currency
          scaled = amount * (10 ^ digits)
       in case toBoundedInteger scaled :: Maybe Int of
            Nothing ->
              Left $
                "amount has more precision than "
                  <> renderCurrency currency
                  <> " supports ("
                  <> T.pack (show digits)
                  <> " decimal place(s))"
            Just minorUnits -> Right (Money (toInteger minorUnits) currency)

-- | Render as a human-readable, thousands-separated string, e.g.
-- @formatMoney (Money 123456 USD) == "$1,234.56"@.
formatMoney :: Money -> Text
formatMoney (Money minorUnits currency) =
  let digits = minorUnitDigits currency
      divisor = 10 ^ digits :: Integer
      whole = abs minorUnits `div` divisor
      fraction = abs minorUnits `mod` divisor
      wholeText = groupThousands (show whole)
      fractionText
        | digits == 0 = ""
        | otherwise = "." <> padLeft digits '0' (show fraction)
   in currencySymbol currency <> T.pack wholeText <> T.pack fractionText

padLeft :: Int -> Char -> String -> String
padLeft n c s = replicate (max 0 (n - length s)) c <> s

-- | Insert commas every three digits from the right: @"1234567" -> "1,234,567"@.
groupThousands :: String -> String
groupThousands = intercalate "," . reverse . map reverse . chunksOf 3 . reverse
  where
    chunksOf _ [] = []
    chunksOf n xs = take n xs : chunksOf n (drop n xs)

--------------------------------------------------------------------------------
-- Transaction type
--------------------------------------------------------------------------------

data TransactionType = Deposit | Withdrawal | Transfer | Payment
  deriving (Eq, Show, Enum, Bounded)

parseTransactionType :: Text -> Either Text TransactionType
parseTransactionType raw = case T.toUpper (T.strip raw) of
  "DEPOSIT" -> Right Deposit
  "WITHDRAWAL" -> Right Withdrawal
  "TRANSFER" -> Right Transfer
  "PAYMENT" -> Right Payment
  other ->
    Left $
      "unsupported transaction type \"" <> other
        <> "\" (supported: DEPOSIT, WITHDRAWAL, TRANSFER, PAYMENT)"

renderTransactionType :: TransactionType -> Text
renderTransactionType = T.toUpper . T.pack . show

--------------------------------------------------------------------------------
-- Account identifiers
--------------------------------------------------------------------------------

-- | A validated account number: 8-17 upper-case alphanumeric characters,
-- matching the shape of a typical IBAN/account identifier without tying
-- this demo to one country's actual checksum rules.
newtype AccountId = AccountId {unAccountId :: Text}
  deriving (Eq, Show)

mkAccountId :: Text -> Either Text AccountId
mkAccountId raw
  | T.any isSpace raw =
      Left "account id must not contain whitespace"
  | len < 8 || len > 17 =
      Left "account id must be 8-17 characters long"
  | not (T.all isAlphaNum normalized) =
      Left "account id must be alphanumeric"
  | otherwise = Right (AccountId normalized)
  where
    normalized = T.toUpper raw
    len = T.length normalized

--------------------------------------------------------------------------------
-- Wire types: what comes in, what goes out
--------------------------------------------------------------------------------

-- | The raw shape of an incoming transaction request. Deliberately
-- "stringly typed" (Text/Scientific rather than 'Currency'/'Money') so
-- that JSON decoding always succeeds and every field-level problem can be
-- collected and reported together, instead of aeson bailing out on the
-- first bad field.
data TransactionRequest = TransactionRequest
  { reqAccountId :: Text
  , reqType :: Text
  , reqAmount :: Scientific
  , reqCurrency :: Text
  , reqDescription :: Text
  , reqCounterparty :: Maybe Text
  }
  deriving (Show, Generic)

instance FromJSON TransactionRequest where
  parseJSON = genericParseJSON jsonOptions

jsonOptions :: Options
jsonOptions =
  defaultOptions
    { fieldLabelModifier = dropPrefixAndLower "req"
    , omitNothingFields = True
    }

-- | Drop a known prefix from a Haskell field name and lower-case the next
-- letter, e.g. @dropPrefixAndLower "req" "reqAccountId" == "accountId"@.
dropPrefixAndLower :: String -> String -> String
dropPrefixAndLower prefix field =
  case drop (length prefix) field of
    (c : cs) -> toUpper' False c : cs
    [] -> field
  where
    toUpper' _ c
      | isUpper c = toLowerChar c
      | isDigit c = c
      | otherwise = c
    toLowerChar c = toEnum (fromEnum c + 32)

data TransactionStatus = Approved | Declined
  deriving (Eq, Show)

instance ToJSON TransactionStatus where
  toJSON Approved = String "APPROVED"
  toJSON Declined = String "DECLINED"

-- | Flags raised by simple, explainable heuristics — not a real fraud
-- model, just enough to show the response shape carrying more than a
-- bare pass/fail.
data RiskFlag
  = LargeAmount
  | SelfTransfer
  | RoundNumber
  deriving (Eq, Show)

renderRiskFlag :: RiskFlag -> Text
renderRiskFlag LargeAmount = "LARGE_AMOUNT"
renderRiskFlag SelfTransfer = "SELF_TRANSFER"
renderRiskFlag RoundNumber = "ROUND_NUMBER"

instance ToJSON RiskFlag where
  toJSON = String . renderRiskFlag

-- | The formatted, validated response returned to the client.
data TransactionResponse = TransactionResponse
  { respTransactionId :: Text
  , respStatus :: TransactionStatus
  , respAccountId :: Maybe Text
  , respType :: Maybe Text
  , respAmountMinorUnits :: Maybe Integer
  , respAmountFormatted :: Maybe Text
  , respCurrency :: Maybe Text
  , respDescription :: Maybe Text
  , respCounterparty :: Maybe Text
  , respRiskFlags :: [RiskFlag]
  , respErrors :: [Text]
  , respReceivedAt :: UTCTime
  }
  deriving (Show, Generic)

instance ToJSON TransactionResponse where
  toJSON = genericToJSON respJsonOptions
  toEncoding = genericToEncoding respJsonOptions

respJsonOptions :: Options
respJsonOptions =
  defaultOptions
    { fieldLabelModifier = dropPrefixAndLower "resp"
    , omitNothingFields = True
    }
