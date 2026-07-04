{-# LANGUAGE OverloadedStrings #-}

-- | Turns a raw, "stringly typed" 'TransactionRequest' into either a
-- rejected 'TransactionResponse' carrying every validation error found,
-- or an approved one carrying the normalized, formatted transaction.
--
-- The interesting bit here is 'Validated': a tiny hand-rolled applicative
-- that accumulates errors instead of stopping at the first one, so a
-- client that gets everything wrong finds out everything that's wrong in
-- one round trip instead of fixing fields one at a time. This is the same
-- shape as the @Validation@ type from the @validation@/@these@ packages;
-- it's inlined here because one function doesn't justify the dependency.
module Banking.Validation (processTransaction) where

import Banking.Types
import Control.Monad (replicateM)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import System.Random (randomRIO)

-- | Like 'Either' with a list of errors on the failing side, but the
-- 'Applicative' instance accumulates errors from both sides instead of
-- short-circuiting at the first failure — that's the whole point.
data Validated a = Invalid [Text] | Valid a

instance Functor Validated where
  fmap f (Valid a) = Valid (f a)
  fmap _ (Invalid es) = Invalid es

instance Applicative Validated where
  pure = Valid
  Valid f <*> Valid a = Valid (f a)
  Invalid e1 <*> Invalid e2 = Invalid (e1 <> e2)
  Invalid e1 <*> Valid _ = Invalid e1
  Valid _ <*> Invalid e2 = Invalid e2

fromEither :: Either Text a -> Validated a
fromEither (Left e) = Invalid [e]
fromEither (Right a) = Valid a

-- | Validate the request and, on success, produce an approved response;
-- on failure, a declined response listing every problem found. Runs in
-- 'IO' only to draw a timestamp and a random id suffix.
processTransaction :: TransactionRequest -> UTCTime -> IO TransactionResponse
processTransaction req now = do
  txnId <- generateTransactionId now
  pure $ case validate req of
    Invalid errs -> declinedResponse txnId errs now
    Valid (accId, txnType, money, desc, counterparty) ->
      TransactionResponse
        { respTransactionId = txnId
        , respStatus = Approved
        , respAccountId = Just (unAccountId accId)
        , respType = Just (renderTransactionType txnType)
        , respAmountMinorUnits = Just (moneyMinorUnits money)
        , respAmountFormatted = Just (formatMoney money)
        , respCurrency = Just (renderCurrency (moneyCurrency money))
        , respDescription = Just desc
        , respCounterparty = counterparty
        , respRiskFlags = riskFlags txnType money accId counterparty
        , respErrors = []
        , respReceivedAt = now
        }

validate ::
  TransactionRequest ->
  Validated (AccountId, TransactionType, Money, Text, Maybe Text)
validate req =
  case (,,,) <$> fromEither (mkAccountId (reqAccountId req))
    <*> fromEither (parseTransactionType (reqType req))
    <*> fromEither (parseCurrency (reqCurrency req))
    <*> validateDescription (reqDescription req) of
    Invalid errs -> Invalid errs
    Valid (accId, txnType, currency, desc) ->
      case (,) <$> fromEither (mkMoney (reqAmount req) currency)
        <*> validateCounterparty txnType (reqCounterparty req) of
        Invalid errs -> Invalid errs
        Valid (money, counterparty) ->
          Valid (accId, txnType, money, desc, counterparty)

validateDescription :: Text -> Validated Text
validateDescription raw
  | T.null trimmed = Invalid ["description must not be empty"]
  | T.length trimmed > 140 = Invalid ["description must be 140 characters or fewer"]
  | otherwise = Valid trimmed
  where
    trimmed = T.strip raw

validateCounterparty :: TransactionType -> Maybe Text -> Validated (Maybe Text)
validateCounterparty Transfer Nothing =
  Invalid ["counterparty is required for TRANSFER transactions"]
validateCounterparty Transfer (Just cp) =
  case mkAccountId cp of
    Left e -> Invalid [e]
    Right validCp -> Valid (Just (unAccountId validCp))
validateCounterparty _ maybeCp = Valid maybeCp

-- | Simple, explainable heuristics — not a real fraud model, just enough
-- to show the response shape carrying more than a bare pass/fail.
riskFlags :: TransactionType -> Money -> AccountId -> Maybe Text -> [RiskFlag]
riskFlags txnType money accId counterparty =
  concat
    [ [LargeAmount | isLarge]
    , [SelfTransfer | isSelfTransfer]
    , [RoundNumber | isRoundNumber]
    ]
  where
    currency = moneyCurrency money
    digits = minorUnitDigits currency
    largeThreshold = 10000 * (10 ^ digits)
    isLarge = moneyMinorUnits money >= largeThreshold
    isSelfTransfer =
      txnType == Transfer && counterparty == Just (unAccountId accId)
    isRoundNumber =
      digits > 0 && moneyMinorUnits money `mod` (10 ^ digits) == 0

declinedResponse :: Text -> [Text] -> UTCTime -> TransactionResponse
declinedResponse txnId errs now =
  TransactionResponse
    { respTransactionId = txnId
    , respStatus = Declined
    , respAccountId = Nothing
    , respType = Nothing
    , respAmountMinorUnits = Nothing
    , respAmountFormatted = Nothing
    , respCurrency = Nothing
    , respDescription = Nothing
    , respCounterparty = Nothing
    , respRiskFlags = []
    , respErrors = errs
    , respReceivedAt = now
    }

-- | e.g. @TXN-20260701-4Q7ZKD@ — a date for readability plus a random
-- suffix. Good enough for a demo; a production system would want
-- something collision-proof and auditable (a ULID, or a DB sequence).
generateTransactionId :: UTCTime -> IO Text
generateTransactionId now = do
  suffix <- T.pack <$> replicateM 6 randomAlnumChar
  let datePart = T.pack (formatTime defaultTimeLocale "%Y%m%d" now)
  pure ("TXN-" <> datePart <> "-" <> suffix)

randomAlnumChar :: IO Char
randomAlnumChar = do
  i <- randomRIO (0, length alphabet - 1)
  pure (alphabet !! i)
  where
    alphabet = ['A' .. 'Z'] ++ ['0' .. '9']
