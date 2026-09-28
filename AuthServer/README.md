# Auth server

Implements `GET /challenge`, `POST /register`, `GET /session/nonce`,
`POST /session` per `Architecture/architecture-decisions.md` §6 and
`Architecture/attestation-assertion-workflow.md`. Design rationale (language
choice, the `clientDataHash` trade-off) is in
`Architecture/account-keys-reference.md`.

## Run locally

```
cp .env.example .env   # fill in APPATTEST_TEAM_ID / APPATTEST_BUNDLE_ID
docker compose up --build
```

Server on `http://localhost:8080`. Postgres and Redis are throwaway
containers — `docker compose down -v` wipes everything.

## Run without Docker

```
export APPATTEST_TEAM_ID=...
export APPATTEST_BUNDLE_ID=...
export APPATTEST_ENVIRONMENT=development
export DATABASE_URL=jdbc:postgresql://localhost:5432/authserver
export DATABASE_USER=authserver
export DATABASE_PASSWORD=authserver
export REDIS_URL=redis://localhost:6379
./gradlew run
```

Needs a real Postgres and Redis reachable at those URLs — nothing here
starts embedded/in-memory versions of either.

## Rolling to a real deployment

Every environment-specific value is an env var (`Config.kt`) — nothing else
changes between local and a real deployment. The same `Dockerfile` builds
the same image either way; point `DATABASE_URL`/`REDIS_URL` at managed
instances (or your own VM-hosted ones) and set `APPATTEST_ENVIRONMENT=production`
once the app ships with the production entitlement.

## Not built yet

- TLS termination — assumed to be handled in front of this (a reverse proxy
  or the cloud provider's load balancer), not by this process.
- Rate limiting (architecture-decisions.md §9 — Redis token buckets, IP-based
  pre-attestation, `keyId`-based post-attestation).
- Automated tests. The verification logic itself is exercised by
  `devicecheck-appattest`'s own test suite; what's untested here is the
  wiring (routes, Redis single-use semantics, the idempotent upsert). Worth
  a Testcontainers-based integration suite before this goes anywhere near
  production traffic.
