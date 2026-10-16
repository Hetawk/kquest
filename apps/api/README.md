# KINGDOM Quest API

The API is a Rails 8.1 application backed by PostgreSQL. From this directory:

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Configure `DATABASE_URL` for the primary database. Production cache, queue, and
cable connections use that URL by default; set `CACHE_DATABASE_URL`,
`QUEUE_DATABASE_URL`, or `CABLE_DATABASE_URL` only when those roles need
dedicated databases.

Launchpad detects the Rails API and SvelteKit web app as separate services,
runs `db:prepare` before starting the API, and routes `/api/` to Rails. Set the
production `WEB_APP_URL` and Google OAuth callback URL to the configured
application domain. Provider keys and mail/assets credentials belong in
Launchpad's encrypted production environment, not in the repository.

Run the API suite with:

```sh
bin/rails test
```
