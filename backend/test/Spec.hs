{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Banking.Types
import Banking.Validation (processTransaction)
import Data.Scientific (scientific)
import Data.Time (getCurrentTime)
import System.Exit (exitFailure, exitSuccess)
import Test.HUnit
import Test.QuickCheck

--------------------------------------------------------------------------------
-- Unit tests (HUnit): one behaviour per test, named after what it protects.
--------------------------------------------------------------------------------

unitTests :: Test
unitTests =
  TestList
    [ TestLabel "account id rejects too short" $
        TestCase (mkAccountId "SHORT" @?= Left "account id must be 8-17 characters long")
    , TestLabel "account id rejects whitespace" $
        TestCase
          ( mkAccountId "AB CDE123"
              @?= Left "account id must not contain whitespace"
          )
    , TestLabel "account id rejects non-alphanumeric" $
        TestCase
          ( mkAccountId "ACCT-1234"
              @?= Left "account id must be alphanumeric"
          )
    , TestLabel "account id normalizes case" $
        TestCase (fmap unAccountId (mkAccountId "acct12345") @?= Right "ACCT12345")
    , TestLabel "money rejects zero and negative amounts" $
        TestCase $ do
          mkMoney 0 USD @?= Left "amount must be a positive number"
          mkMoney (-5) USD @?= Left "amount must be a positive number"
    , TestLabel "money rejects sub-cent precision" $
        TestCase
          ( mkMoney (scientific 12345 (-3)) USD
              @?= Left "amount has more precision than USD supports (2 decimal place(s))"
          )
    , TestLabel "money rejects fractional yen" $
        TestCase
          ( mkMoney (scientific 505 (-1)) JPY
              @?= Left "amount has more precision than JPY supports (0 decimal place(s))"
          )
    , TestLabel "formatMoney adds thousands separators" $
        TestCase (formatMoney (either (error "bad fixture") id (mkMoney 1234567.89 USD)) @?= "$1,234,567.89")
    , TestLabel "formatMoney handles a currency with no minor unit" $
        TestCase (formatMoney (either (error "bad fixture") id (mkMoney 5000 JPY)) @?= "¥5,000")
    , TestLabel "currency parsing is case-insensitive" $
        TestCase (parseCurrency "usd" @?= Right USD)
    , TestLabel "transaction type parsing is case-insensitive" $
        TestCase (parseTransactionType "Deposit" @?= Right Deposit)
    , TestLabel "unsupported currency names the offending code" $
        TestCase
          ( parseCurrency "BTC"
              @?= Left "unsupported currency \"BTC\" (supported: USD, EUR, GBP, JPY)"
          )
    ]

--------------------------------------------------------------------------------
-- Integration-flavoured tests through the public entry point.
--------------------------------------------------------------------------------

processTests :: Test
processTests =
  TestList
    [ TestLabel "invalid request accumulates every field error, not just the first" $
        TestCase $ do
          now <- getCurrentTime
          resp <-
            processTransaction
              TransactionRequest
                { reqAccountId = "bad id"
                , reqType = "yeet"
                , reqAmount = -5
                , reqCurrency = "XYZ"
                , reqDescription = ""
                , reqCounterparty = Nothing
                }
              now
          respStatus resp @?= Declined
          length (respErrors resp) @?= 4
    , TestLabel "a well-formed deposit is approved with no risk flags" $
        TestCase $ do
          now <- getCurrentTime
          resp <-
            processTransaction
              TransactionRequest
                { reqAccountId = "acct12345"
                , reqType = "deposit"
                , reqAmount = 42.50
                , reqCurrency = "USD"
                , reqDescription = "Paycheck"
                , reqCounterparty = Nothing
                }
              now
          respStatus resp @?= Approved
          respRiskFlags resp @?= []
    , TestLabel "a transfer to the same account is flagged, not rejected" $
        TestCase $ do
          now <- getCurrentTime
          resp <-
            processTransaction
              TransactionRequest
                { reqAccountId = "acct12345"
                , reqType = "transfer"
                , reqAmount = 10
                , reqCurrency = "USD"
                , reqDescription = "oops"
                , reqCounterparty = Just "acct12345"
                }
              now
          respStatus resp @?= Approved
          SelfTransfer `elem` respRiskFlags resp @?= True
    ]

--------------------------------------------------------------------------------
-- Property test (QuickCheck): the amount pipeline round-trips.
--
-- For any positive number of cents, building a Money from that many cents
-- (expressed as a decimal amount) and reading moneyMinorUnits back off it
-- must reproduce the original integer exactly. This is the property that
-- justifies storing money as minor-unit integers in the first place: no
-- amount should ever drift by a cent between "what came in" and "what we
-- stored".
--------------------------------------------------------------------------------

prop_moneyRoundTrips :: Positive Integer -> Property
prop_moneyRoundTrips (Positive cents) =
  case mkMoney (scientific cents (-2)) USD of
    Left err -> counterexample ("unexpected rejection: " <> show err) False
    Right money -> moneyMinorUnits money === cents

--------------------------------------------------------------------------------

main :: IO ()
main = do
  hunitCounts <- runTestTT (TestList [unitTests, processTests])
  qcResult <- quickCheckResult (withMaxSuccess 500 prop_moneyRoundTrips)
  let hunitOk = errors hunitCounts == 0 && failures hunitCounts == 0
      qcOk = case qcResult of
        Success {} -> True
        _ -> False
  if hunitOk && qcOk then exitSuccess else exitFailure
