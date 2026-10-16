# KINGDOM Quest

KINGDOM Quest is an educational gaming and assessment platform. The initial
architecture is a modular Rails API, a SvelteKit web app, and PostgreSQL, as
specified in [`kingdom_quest.md`](./kingdom_quest.md).

## Project layout

- `apps/api` — Rails 8 API, Minitest, and PostgreSQL persistence.
- `apps/web` — SvelteKit and TypeScript frontend, Vitest, and Playwright.
- `docs/api` — versioned REST API contract.

Business logic belongs in cohesive domain modules under `apps/api/app/domains`.
Controllers are delivery adapters, and the server remains authoritative for
permissions, grading, and scoring.

## Requirements

- Ruby 4.0.7 and Bundler.
- Node.js 22.12 or newer and npm.
- PostgreSQL for local development and tests.

On Apple Silicon with Homebrew Ruby, make the Homebrew Ruby and gem executables
available in the current shell:

```sh
export PATH="$(brew --prefix ruby)/bin:$(brew --prefix)/lib/ruby/gems/4.0.0/bin:$PATH"
ruby --version
```

## Setup

The root `.env` is private and ignored by Git. For a new checkout, copy
`.env.example` to `.env` and set `DATABASE_URL` to a dedicated development
database. The Rails API loads this root file in development only. Tests use
`TEST_DATABASE_URL` when provided, otherwise the local `api_test` database;
they do not load the development `.env`.

```sh
cd apps/api
bundle config set --local path .bundle
bundle install
```

```sh
npm ci --prefix apps/web
```

Before running any migration or database preparation command, verify that
`DATABASE_URL` points to the intended development database and that its
existing data is safe to preserve. Never use the development database as the
test database.

## Run locally

From the repository root, with the Ruby path set as above:

```sh
cd apps/api
bin/rails server
```

In another terminal:

```sh
npm run dev:web
```

The API exposes the Rails process health check at `/up` and a versioned API
health response at `/api/v1/health`. Neither endpoint exposes database
credentials or learner data.

## Learning journey prototype

The first end-to-end flow supports creating and publishing a single-choice
quest, joining by share code, answering questions, and viewing a server-graded
result. Activity creation, publication, gameplay lookup, and attempt submission
are deliberately available only in Rails development and test environments.
They return `404` in production until educator authentication, organization
authorization, and abuse protections are implemented. Do not expose this
prototype API as a production service.

The decorative Three.js scene is not required for gameplay and respects reduced
motion preferences. The API contract is in [`docs/api/openapi.yaml`](./docs/api/openapi.yaml).

## Checks

```sh
npm run check:web
npm run lint:web
npm run test:web
npm run build:web
```

From `apps/api`, run `RAILS_ENV=test bin/rails test`, `bin/rubocop`, and
`bin/brakeman --no-pager`. Rails database-backed tests require a separate,
disposable test database.
