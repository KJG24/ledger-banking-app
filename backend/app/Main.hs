module Main (main) where

import Banking.Api (app)
import System.Environment (lookupEnv)
import System.IO (BufferMode (LineBuffering), hSetBuffering, stdout)
import Text.Read (readMaybe)
import Web.Scotty (scotty)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  port <- maybe 8080 id . (>>= readMaybe) <$> lookupEnv "PORT"
  putStrLn ("banking-backend: listening on port " <> show port)
  putStrLn ("banking-backend: POST http://localhost:" <> show port <> "/api/transactions")
  scotty port app
