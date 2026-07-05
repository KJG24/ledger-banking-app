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
easiest way to get both) and Node.js, ideally via
[nvm](https://github.com/nvm-sh/nvm) — the frontend's `.nvmrc` pins the
exact version this was built against.

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
nvm install   # reads .nvmrc, installs/switches to Node 22.22.2
nvm use
npm install
npm run dev
# ➜  Local:   http://localhost:5173/
```

If you don't have `nvm`, any Node 18+ works fine — `.nvmrc`/`engines` just
pin an exact version for reproducibility; `npm` is still what actually
installs dependencies and runs the dev server.

Open `http://localhost:5173`. The frontend talks to `http://localhost:8080`
by default; copy `.env.example` to `.env` to point it somewhere else.

### Troubleshooting: `cannot find -lgmp`

If `cabal build` fails partway through with a linker error like:

```
/usr/bin/ld: cannot find -lgmp: No such file or directory
```

that's a missing **system** library, not a problem with this project —
GHC needs the GMP arithmetic library to link anything, and on a fresh
machine it's often not installed yet. Install it and re-run `cabal build`
(cabal resumes from where it left off, it doesn't start over):

```bash
sudo apt-get install libgmp-dev      # Ubuntu/Debian, incl. WSL
sudo dnf install gmp-devel           # Fedora/RHEL
sudo pacman -S gmp                   # Arch
brew install gmp                     # macOS
```

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

## Deploying a live demo

GitHub Pages only serves static files, so the split is: **frontend on
Pages**, **backend on a host that can run a process**. Deploy the backend
first — the frontend's build needs its URL.

### 1. Backend → Render

Render's free web-service tier is the one still offering genuinely free,
no-credit-card hosting as of this writing; Railway and Fly.io have both
moved to paid-only or trial-credit models. The trade-off: a free Render
service spins down after 15 minutes of inactivity and takes 30-50 seconds
to wake back up on the next request. Fine for a portfolio demo, worth
knowing before you send someone a link.

1. Push this repo to GitHub if you haven't already.
2. Create a free account at [render.com](https://render.com) (no card
   required) and connect your GitHub account.
3. **New > Web Service**, select this repo.
4. Set:
   - **Root Directory**: `backend`
   - **Runtime**: `Docker` (Render should auto-detect the `Dockerfile`)
   - **Instance Type**: `Free`
5. Deploy. First build takes a few minutes (compiling GHC dependencies
   from scratch). Once it's up, note the public URL Render gives you —
   something like `https://ledger-banking-backend.onrender.com`.
6. Confirm it's alive: `curl https://<your-url>/api/health` should
   return `{"status":"ok"}` (give it 30-50 seconds if it's been idle).

A `render.yaml` Blueprint is included at the repo root if you'd rather
manage this as code — see the comment in that file for a known rough
edge with monorepo Docker paths before relying on it.

### 2. Frontend → GitHub Pages

1. In the repo's **Settings > Pages**, set **Source** to
   **GitHub Actions**.
2. In **Settings > Secrets and variables > Actions > Variables**, add a
   repository variable named `VITE_API_BASE_URL` set to the backend URL
   from step 1 (no trailing slash).
3. Push to `main` (or run the "Deploy frontend to GitHub Pages" workflow
   manually from the Actions tab). `.github/workflows/deploy-pages.yml`
   builds the frontend and deploys it automatically.
4. Your site will be live at `https://<your-username>.github.io/<repo-name>/`.

If you change `VITE_API_BASE_URL` later, re-run the workflow manually —
it's a build-time value baked into the static bundle, not read at
runtime.

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
