{-# LANGUAGE OverloadedStrings #-}

-- | HTTP surface for the demo: one health check, one transaction endpoint.
module Banking.Api (app) where

import Banking.Types (TransactionRequest, TransactionResponse (respStatus), TransactionStatus (..))
import Banking.Validation (processTransaction)
import Data.Aeson (object, (.=))
import qualified Data.Text.Lazy as TL
import Data.Time (getCurrentTime)
import Network.HTTP.Types.Status (badRequest400, ok200)
import Network.Wai.Middleware.Cors
  ( CorsResourcePolicy (corsRequestHeaders)
  , cors
  , simpleCorsResourcePolicy
  , simpleHeaders
  )
import Web.Scotty

app :: ScottyM ()
app = do
  -- The frontend is served from a different origin during local
  -- development (Vite on :5173, this API on :8080), so it needs CORS.
  -- 'simpleCors' isn't enough here: it only allows the CORS-spec "simple"
  -- headers (Accept, Accept-Language, Content-Language), and a JSON POST
  -- sends "Content-Type: application/json", which triggers a preflight
  -- that simpleCors would then reject. Widening corsRequestHeaders to
  -- include Content-Type is what actually lets the browser through.
  middleware $
    cors
      ( const . Just $
          simpleCorsResourcePolicy
            { corsRequestHeaders = "Content-Type" : simpleHeaders
            }
      )

  get "/api/health" $
    json $ object ["status" .= ("ok" :: TL.Text)]

  post "/api/transactions" $ do
    maybeReq <- (Just <$> jsonData) `catch` jsonParseFailed
    case maybeReq of
      Nothing -> do
        status badRequest400
        json $
          object
            [ "error"
                .= ( "request body is not valid JSON, or is missing/mis-typed fields"
                       :: TL.Text
                   )
            ]
      Just req -> do
        now <- liftIO getCurrentTime
        resp <- liftIO (processTransaction (req :: TransactionRequest) now)
        status (if respStatus resp == Approved then ok200 else badRequest400)
        json resp

-- | scotty >=0.20 reports a failed 'jsonData' parse as a 'ScottyException'
-- (e.g. MalformedJSON, FailedToParseJSON) rather than a bare Text error.
-- We don't care which one — any parse failure here just means "tell the
-- client their request body didn't match the expected shape."
jsonParseFailed :: ScottyException -> ActionM (Maybe TransactionRequest)
jsonParseFailed _ = pure Nothing
