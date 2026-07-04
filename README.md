# Ledger

A small full-stack transaction processor: type a transaction into a form,
a Haskell backend validates and normalizes it, and the formatted JSON
comes back and gets stamped into a running ledger.

```
┌─────────────────────────┐        POST /api/transactions        ┌──────────────────────────┐
│   React + TypeScript    │ ─────────────────────────────────────▶│   Haskell (Scotty)       │
│   Redux Toolkit         │                                       │   Aeson · WAI · Warp     │
│   (Vite, :5173)         │ ◀───────────────────────────────────── │   (:8080)                │
└─────────────────────────┘         formatted JSON response       └──────────────────────────┘
```

## What it does

You fill out a transaction — account, type, amount, currency, description,
and (for transfers) a counterparty — and submit it. The backend:

1. Parses the request into precise domain types (`AccountId`, `Currency`,
   `Money`, `TransactionType`) via smart constructors, each of which can
   reject malformed input with a specific reason.
2. Accumulates **every** validation error at once, instead of stopping at
   the first one, using a small hand-rolled applicative (see
   `Banking.Validation`).
3. On success, computes a formatted, normalized response — money is
   stored as integer minor units (cents), never floating point — and
   flags a couple of simple, explainable risk heuristics.
4. Returns the result as JSON, which the frontend renders as a stamped
   receipt and appends to a session ledger.

A declined transaction isn't an error from the API's point of view — it's
a normal, well-formed response that just says `"status": "DECLINED"` and
lists what was wrong. Only a genuinely malformed request body (bad JSON,
missing fields) gets treated as an actual error.

## Stack

| Layer     | Choices                                                   |
| --------- | ---------------------------------------------------------- |
| Backend   | Haskell, Scotty, Aeson, WAI/Warp, wai-cors                  |
| Testing   | HUnit (unit tests), QuickCheck (property test)              |
| Frontend  | React 19, TypeScript, Redux Toolkit, Vite                   |

## Quick start

You'll need GHC + Cabal ([ghcup](https://www.haskell.org/ghcup/) is the
easiest way to get both) and Node 18+.

**Backend** (from `backend/`):

```bash
cabal build
cabal run banking-backend
# banking-backend: listening on port 8080
```

If you'd rather not wait on `cabal`'s dependency resolution, everything
this project uses also ships as an Ubuntu/Debian package, which is how it
was actually built and tested end-to-end during development:

```bash
sudo apt-get install ghc libghc-scotty-dev libghc-aeson-dev \
  libghc-wai-cors-dev libghc-warp-dev libghc-wai-dev libghc-http-types-dev \
  libghc-hunit-dev libghc-quickcheck2-dev
ghc -O1 -isrc -iapp -odir build -hidir build -o build/banking-backend app/Main.hs
./build/banking-backend
```

**Frontend** (from `frontend/`, in another terminal):

```bash
npm install
npm run dev
# ➜  Local:   http://localhost:5173/
```

Open `http://localhost:5173`. The frontend talks to `http://localhost:8080`
by default; copy `.env.example` to `.env` to point it somewhere else.

## Running the tests

```bash
cd backend
cabal test
# or, without cabal's dependency resolution:
ghc -O0 -isrc -itest -odir build-test -hidir build-test -o build-test/spec test/Spec.hs
./build-test/spec
```

15 unit tests cover the domain types and validation rules directly; one
QuickCheck property (500 random cases) checks that the money pipeline
round-trips exactly — that converting a decimal amount to minor units and
back never drifts by a cent.

## API

### `POST /api/transactions`

```bash
curl -s http://localhost:8080/api/transactions \
  -H "Content-Type: application/json" \
  -d '{
    "accountId": "acct12345",
    "type": "deposit",
    "amount": 2500.50,
    "currency": "usd",
    "description": "Paycheck deposit"
  }'
```

```json
{
  "transactionId": "TXN-20260701-EHOO33",
  "status": "APPROVED",
  "accountId": "ACCT12345",
  "type": "DEPOSIT",
  "amountMinorUnits": 250050,
  "amountFormatted": "$2,500.50",
  "currency": "USD",
  "description": "Paycheck deposit",
  "riskFlags": [],
  "errors": [],
  "receivedAt": "2026-07-01T03:58:35.901873502Z"
}
```

A request with several problems at once gets every problem back at once:

```json
{
  "transactionId": "TXN-20260701-42TLHD",
  "status": "DECLINED",
  "riskFlags": [],
  "errors": [
    "account id must not contain whitespace",
    "unsupported transaction type \"YEET\" (supported: DEPOSIT, WITHDRAWAL, TRANSFER, PAYMENT)",
    "unsupported currency \"XYZ\" (supported: USD, EUR, GBP, JPY)",
    "description must not be empty"
  ],
  "receivedAt": "2026-07-01T03:58:48.293161724Z"
}
```

`type` and `currency` are case-insensitive; `counterparty` is required
(and validated as an account id) only when `type` is `TRANSFER`.

### `GET /api/health`

Returns `{"status": "ok"}`. Useful for confirming the backend is up
before poking at the frontend.

## Project structure

```
backend/
  app/Main.hs                 entry point, port selection
  src/Banking/
    Types.hs                  domain types + smart constructors + JSON instances
    Validation.hs             accumulating validation, risk flags, id generation
    Api.hs                    Scotty routes + CORS
  test/Spec.hs                HUnit + QuickCheck
  banking-backend.cabal

frontend/
  src/
    api/transactions.ts       fetch wrapper, distinguishes declines from real errors
    app/store.ts, hooks.ts    Redux store + typed hooks
    features/transactions/
      types.ts                types mirroring the backend's JSON exactly
      transactionsSlice.ts    async thunk + reducers (history, current, status)
      TransactionForm.tsx     the input side
      TransactionReceipt.tsx  the stamped JSON output
      TransactionJournal.tsx  session history, click a row to revisit it
    App.tsx, main.tsx
```

## Notes on a few design choices

- **Money is never a float.** `Money` stores an `Integer` count of the
  currency's minor unit (cents, or nothing for yen). `mkMoney` is the only
  way to construct one, and it rejects amounts with more precision than
  the currency supports — so `50.555 USD` or `12.5 JPY` are caught at the
  boundary, not silently rounded somewhere downstream.
- **Validation accumulates.** `Banking.Validation` hand-rolls a tiny
  `Validated` applicative (`Invalid [Text] | Valid a`) instead of pulling
  in a dependency for one function's worth of use — the point being that
  a request with four things wrong gets told about all four, not just the
  first one `Either` would have stopped at.
- **A decline is data, not an exception.** Both the backend (200 vs. 400
  by outcome, but always a real `TransactionResponse` body) and the
  frontend (`postTransaction` only throws for a genuinely malformed
  response) treat "the transaction was invalid" as a normal, displayable
  result rather than an error path.
