# syntax=docker/dockerfile:1

# Multi-stage build: compile with the full GHC toolchain, ship only the
# resulting binary + its runtime C libraries.
#
# Pinned to GHC 9.10.3 - the exact version this project was last confirmed
# to build against (see the README's cabal troubleshooting notes). Bumping
# this is fine, but expect to re-check the fixes documented there if you do.
FROM haskell:9.10.3 AS builder

WORKDIR /opt/build

# Copy just the cabal file first so `cabal build --only-dependencies` gets
# its own Docker layer, and only reruns when dependencies actually change
# rather than on every source edit.
COPY banking-backend.cabal ./
RUN cabal update && cabal build exe:banking-backend --only-dependencies -j4

COPY . .
RUN cabal build exe:banking-backend
RUN cp "$(cabal list-bin exe:banking-backend)" /opt/build/banking-backend-bin

# --- Runtime image ---------------------------------------------------------
# GHC's Integer implementation links against GMP (see the README's
# "cannot find -lgmp" note - this is the runtime side of that same
# dependency), so the slim runtime image needs libgmp10 even though it
# never runs GHC itself.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgmp10 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /opt/build/banking-backend-bin ./banking-backend

# Render (and most PaaS platforms) inject PORT at runtime; app/Main.hs
# already reads it via lookupEnv, falling back to 8080 for local use.
ENV PORT=8080
EXPOSE 8080

CMD ["./banking-backend"]
