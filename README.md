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

## Learning journey

The learning studio supports creating, ordering, publishing, and sharing
single-choice and multiple-select quests; joining by share code; hosting live
rooms; answering questions; and viewing server-graded results. Multiple-select
answers are scored all-or-nothing when the selected set exactly matches the
answer key. The authenticated dashboard is the default landing page after
sign-in. Quest detail workspaces show the question library and answer key to
the owner; published quests are immutable, so editing starts from a separate
copy. Page and workspace loading states respect reduced-motion preferences.
There is no subscription-plan cap on the number of quests or live-room
participants. Sign-in supports Google OAuth and
email/password accounts with
opaque, database-backed sessions in encrypted, HTTP-only, same-site cookies.
Email accounts must verify a one-time code before sign-in; password recovery
uses a separate one-time code. Google email addresses must be verified;
account linking by matching email is deliberately not automatic. Activity
ownership is tied to the signed-in user.

OAuth and provider configuration is loaded only by the Rails server. Set
`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`, and
`WEB_APP_URL` in the ignored root `.env`, and register the redirect URI with
Google. For `https://kquest.ekddigital.com`, the authorized Google redirect
URI must exactly be
`https://kquest.ekddigital.com/api/v1/auth/google_oauth2/callback`; the
similarly named `/api/auth/callback/google` path is not a Kquest endpoint.

Verification, recovery, and welcome messages use EKDSend. Configure
`EKDSEND_API_URL`, `EKDSEND_API_KEY`, and `FROM_EMAIL`; production mail jobs use
Solid Queue, so run `apps/api/bin/jobs start` alongside the API. Verification
and recovery codes expire after 10 minutes, allow five attempts, and are
rate-limited; passwords must be at least 12 characters and at most 72 bytes.

Educators can optionally upload PNG, JPEG, or WebP quest cover images (up to
5 MB) through the authenticated Rails API proxy. Configure `ASSETS_API_URL`
and `ASSETS_API_SECRET`. The API key identifier is not used as an upload
credential. The Assets API secret never reaches the browser. Published cover
images use the Assets service's public URL, so do not upload private or
sensitive images.

### Timed questions and sound

Each new question defaults to 30 seconds. Educators can choose a limit from
5–300 seconds for each question or turn that question's timer off. Published
quests freeze these settings. The server enforces deadlines; timed-out answers
are recorded as unanswered and score zero. The learner countdown and answer
requests are retry-safe.

The player starts its original, soft ambient audio only after the learner
starts the quest. A sound control remains available during play; gentle ticks
are limited to the last five seconds, and answer cues follow server feedback.
Sound is optional, audio failures do not block play, and audio stops when the
quest ends. Howler.js is loaded only in the browser through Svelte's mount
lifecycle. The generated assets can be recreated with
`python3 apps/web/scripts/generate-audio-assets.py`.

Creator APIs require a verified signed-in account and scope activity access to
its owner. Published quests and game codes are public by design so learners
can join without accounts. Organization roles, class-level administration,
and additional anti-abuse controls are not implemented; do not treat a game
code as private content.

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
