# KINGDOM Quest by EKD Digital

## Enterprise Product Requirements, Modular Software Architecture, and SDLC Specification

Version 2.0 · Architecture-led rewrite · Rails + SvelteKit + PostgreSQL

KINGDOM Quest should be designed as a production-grade educational gaming and assessment platform, not merely a quiz application. Its architecture must support teacher-paced games, independent learning, assessments, interactive question types, real-time sessions, analytics, gamification, and future integrations without allowing the codebase to become difficult to maintain.

The central engineering principle is:

Build a modular, contract-driven, validation-first platform with strict separation of concerns, a RESTful API, reusable domain components, and a disciplined software development lifecycle (SDLC).

Every module should have a clear responsibility. Every important business rule should have one authoritative implementation. Every external boundary should validate its inputs. Every integration should use a documented contract. Every significant feature should be testable without requiring the entire platform to run.

This rewrite establishes the architecture and implementation standards that the engineering team should follow from the first commit.

## 1. Product vision and identity

[Your Outer World is a Mirror. The Metaphysics of Inner Reality | by The Meraphysician | New Earth Consciousness | Medium](https://images.openai.com/static-rsc-4/Ptrj3OHD64YREmqehmyhAGToYtQO4KU5MV_a692ra8pVIP-mduHVjdDTXBKCFh2x-gaPsyITtrJmNLccEmr5tft0TvdR9U-D4qc7ajvUA6PFDZmqvJ4bd73Nx5i4jdkx9xmRxiFpYKzjs8oc2uO05mHhcsLdTn3wvaJ5IPbyTfI?purpose=inline)

# KINGDOM Quest

An EKD Digital product

An engaging, intelligent, accessible learning platform that empowers educators to create meaningful learning experiences and helps learners grow through discovery, practice, assessment, and achievement.

### Product principles

- Purposeful learning: game mechanics should reinforce learning rather than distract from it.
- Modularity: each domain has a defined responsibility and explicit interface.
- DRY engineering: business rules and shared behavior have one authoritative implementation.
- Validation first: invalid data and unauthorized operations are rejected at system boundaries.
- RESTful integration: APIs are resource-oriented, predictable, documented, and versioned.
- Security by design: authorization, tenant isolation, privacy, and auditability are built in.
- Accessible interaction: keyboard access, assistive technologies, reduced motion, and responsive layouts are fundamental requirements.
- Respectful pacing: educators control question timers, learners can be given untimed practice, and server-side deadlines are authoritative.
- User-controlled audio: short, original, low-volume cues enhance play without blocking access or competing with assistive technology.
- Scalable architecture: scale through good boundaries, efficient queries, asynchronous work, and measured optimization.
- Kingdom values: stewardship, purpose, integrity, revival, innovation, and trust should be reflected in the product's governance and user experience.

## 2. Architectural decisions

The following decisions establish the initial technical baseline.

| Area                    | Decision                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------- |
| Product architecture    | Modular monolith initially                                                                  |
| Backend                 | Ruby on Rails, API-first                                                                    |
| Backend language        | Ruby                                                                                        |
| Frontend                | SvelteKit + TypeScript                                                                      |
| Database                | PostgreSQL                                                                                  |
| ORM                     | Active Record                                                                               |
| API style               | Versioned REST API with JSON                                                                |
| API contract            | OpenAPI, with generated or validated TypeScript contracts                                   |
| Real-time communication | Action Cable, using REST commands and WebSocket events                                      |
| Background jobs         | Active Job + Solid Queue                                                                    |
| Cache and coordination  | PostgreSQL-backed or in-process solutions initially where appropriate; Redis when justified |
| Media storage           | S3-compatible object storage or equivalent                                                  |
| Validation              | Boundary schemas, domain validation, model validations, and database constraints            |
| Authorization           | Centralized policy-based authorization                                                      |
| Frontend validation     | TypeScript types and runtime schemas                                                        |
| Testing                 | Unit, integration, contract, security, accessibility, and end-to-end tests                  |
| Deployment              | Containerized, automated CI/CD                                                              |
| Observability           | Structured logs, metrics, error tracking, tracing where appropriate                         |

### An important ORM decision

We will use Active Record, not Prisma, for this architecture. Prisma is designed for its supported client and language ecosystems; it is not the appropriate ORM for a Ruby on Rails backend. Active Record provides Rails-native persistence, associations, validations, migrations, and transactions.

If KINGDOM Quest later introduces a separate TypeScript or Go service, that service can use an ORM or database access library appropriate to its language. It should not introduce a second ORM against the same domain tables without a clear ownership and consistency strategy.

### Why a modular monolith first?

A modular monolith allows strong domain boundaries without the operational complexity of many independent services. It simplifies transactions for scoring and submissions, supports straightforward local development, and makes it easier to deliver a complete product.

A modular monolith is not permission to put the entire application in one folder or one enormous service. It requires explicit module ownership, restricted dependencies, small files, and automated architectural checks.

## 3. High-level system architecture

```

flowchart TB
    USER[Educators, Learners, Administrators]
    WEB[SvelteKit Web Application]
    API[REST API - Rails]
    AUTH[Identity and Access]
    CONTENT[Content and Question Engine]
    LEARNING[Assignments and Assessments]
    LIVE[Live Session Domain]
    GAME[Scoring and Gamification]
    REPORTS[Analytics and Reporting]
    INTEGRATIONS[Integration and Webhook Layer]
    DB[(PostgreSQL)]
    JOBS[Background Job Workers]
    OBJECTS[Object Storage]
    EXTERNAL[External Providers]
    TELEMETRY[Logs, Metrics and Traces]

    USER --> WEB
    WEB --> API
    API --> AUTH
    API --> CONTENT
    API --> LEARNING
    API --> LIVE
    API --> GAME
    API --> REPORTS
    API --> INTEGRATIONS
    AUTH --> DB
    CONTENT --> DB
    LEARNING --> DB
    LIVE --> DB
    GAME --> DB
    REPORTS --> DB
    INTEGRATIONS --> EXTERNAL
    API --> JOBS
    JOBS --> DB
    CONTENT --> OBJECTS
    JOBS --> OBJECTS
    JOBS --> EXTERNAL
    WEB --> TELEMETRY
    API --> TELEMETRY
    JOBS --> TELEMETRY

```

These are logical components, not separate applications. In the initial release, Rails hosts the domain modules in one deployable backend. Background workers can run as separate processes using the same application code.

### Architecture rules

1. The frontend never accesses PostgreSQL directly.
2. Controllers never implement complex business workflows.
3. Domain logic does not depend on HTTP request objects.
4. One domain module must not reach into another module's private implementation.
5. All persistent data changes pass through authorized application workflows.
6. External systems are accessed through integration adapters.
7. Database constraints protect critical invariants even when application validations are bypassed.
8. WebSocket events notify clients; they do not replace durable database state.
9. Every module exposes a documented public interface.
10. Independent services are introduced only when a measured need justifies the operational cost.

## 4. Modular codebase architecture

This is the most important design decision in the entire project. KINGDOM Quest must remain easy to understand as the number of features, developers, and integrations increases.

We will use feature-oriented modules, explicit public interfaces, thin delivery layers, and small, cohesive files.

### 4.1 Proposed repository structure

```

kingdom-quest/
├── apps/
│   ├── api/                              # Ruby on Rails backend
│   │   ├── app/
│   │   │   ├── controllers/
│   │   │   │   └── api/v1/
│   │   │   ├── channels/
│   │   │   ├── jobs/
│   │   │   ├── mailers/
│   │   │   └── views/
│   │   │
│   │   ├── config/
│   │   ├── db/
│   │   │   ├── migrate/
│   │   │   ├── schema.rb
│   │   │   └── seeds.rb
│   │   │
│   │   ├── app/domains/
│   │   │   ├── identity/
│   │   │   ├── organizations/
│   │   │   ├── classrooms/
│   │   │   ├── activities/
│   │   │   ├── questions/
│   │   │   ├── assessments/
│   │   │   ├── assignments/
│   │   │   ├── live_sessions/
│   │   │   ├── scoring/
│   │   │   ├── gamification/
│   │   │   ├── analytics/
│   │   │   ├── media/
│   │   │   ├── notifications/
│   │   │   ├── integrations/
│   │   │   └── administration/
│   │   │
│   │   ├── spec/
│   │   │   ├── architecture/
│   │   │   ├── requests/
│   │   │   ├── contracts/
│   │   │   └── support/
│   │   ├── Gemfile
│   │   └── Dockerfile
│   │
│   └── web/                              # SvelteKit frontend
│       ├── src/
│       │   ├── routes/
│       │   ├── lib/
│       │   │   ├── api/
│       │   │   ├── components/
│       │   │   │   ├── ui/
│       │   │   │   ├── forms/
│       │   │   │   ├── feedback/
│       │   │   │   └── navigation/
│       │   │   ├── features/
│       │   │   │   ├── auth/
│       │   │   │   ├── activities/
│       │   │   │   ├── questions/
│       │   │   │   ├── assignments/
│       │   │   │   ├── live-sessions/
│       │   │   │   ├── gamification/
│       │   │   │   └── analytics/
│       │   │   ├── schemas/
│       │   │   ├── stores/
│       │   │   ├── animations/
│       │   │   └── utils/
│       │   └── app.css
│       ├── static/
│       ├── tests/
│       └── package.json
│
├── packages/
│   ├── api-contracts/                    # Generated TS contracts
│   ├── question-schemas/                 # Shared question contracts
│   ├── design-tokens/                    # Brand and motion tokens
│   └── eslint-config/
│
├── docs/
│   ├── product/
│   ├── architecture/
│   ├── decisions/
│   ├── api/
│   ├── data-model/
│   ├── security/
│   ├── testing/
│   └── operations/
│
├── infrastructure/
│   ├── containers/
│   ├── deployment/
│   ├── monitoring/
│   └── scripts/
│
├── .github/workflows/
├── compose.yaml
├── package.json
├── .editorconfig
├── .gitignore
└── README.md

```

The backend directory shown above is a conceptual domain layout, not a requirement to abandon Rails conventions. Rails models, migrations, controllers, channels, jobs, and configuration remain in their conventional locations. Domain-specific application logic is grouped under the configured `app/domains` namespace and loaded through Rails' Zeitwerk autoloader.

### 4.2 Internal structure of every domain

Every substantial domain should follow a consistent pattern. For example, the activities module:

```

app/domains/activities/
├── public_api.rb
├── dependencies.rb
│
├── entities/
│   └── activity.rb
│
├── models/
│   ├── activity_record.rb
│   └── activity_version_record.rb
│
├── contracts/
│   ├── create_activity.rb
│   ├── update_activity.rb
│   └── publish_activity.rb
│
├── services/
│   ├── create_activity.rb
│   ├── update_activity.rb
│   ├── duplicate_activity.rb
│   └── publish_activity.rb
│
├── policies/
│   └── activity_policy.rb
│
├── queries/
│   ├── list_activities.rb
│   └── activity_report.rb
│
├── serializers/
│   ├── activity_serializer.rb
│   └── activity_version_serializer.rb
│
├── events/
│   └── activity_published.rb
│
├── errors/
│   └── errors.rb
│
└── spec/
    ├── services/
    ├── contracts/
    ├── policies/
    └── queries/

```

Not every module needs every directory. The structure should reflect real responsibilities, not generate empty files to satisfy a template.

For small modules, combine closely related responsibilities when doing so improves cohesion. For larger modules, split files as their responsibilities diverge.

### 4.3 Responsibility of each layer

| Layer                | Responsibility                                                                        | Must not do                                                |
| -------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Controller           | Parse HTTP input, authenticate, invoke an application operation, return a response.   | Implement scoring or complex business rules.               |
| Contract/schema      | Validate external input shape and basic constraints.                                  | Decide permissions or persist records.                     |
| Application service  | Orchestrate a use case and transaction boundaries.                                    | Become a general-purpose container for unrelated logic.    |
| Domain object/policy | Enforce business invariants and domain decisions.                                     | Depend on HTTP requests or frontend components.            |
| Active Record model  | Represent persistence, associations, local validations, and database-facing behavior. | Own the entire multi-domain workflow.                      |
| Query object         | Implement a reusable, focused read query.                                             | Perform unrelated mutations.                               |
| Serializer           | Define the public response representation.                                            | Fetch arbitrary data or perform business operations.       |
| Job                  | Execute retryable asynchronous work.                                                  | Assume an in-memory process is the source of truth.        |
| Adapter              | Translate an external provider's interface to an internal contract.                   | Spread provider-specific logic throughout the application. |

### 4.4 Explicit module interfaces

Other modules should interact through public operations, not by depending on internal filenames or private classes.

For example, the assessment module may request a published activity through an interface such as:

```
Activities::PublicAPI.fetch_published_version(
  activity_id: activity_id,
  organization_id: organization_id
)
```

The exact method signature is illustrative. Its contract must define:

- Accepted input types.
- Authorization assumptions.
- Return type.
- Error behavior.
- Whether the operation reads or changes state.
- Transaction expectations.

Avoid a universal `ApplicationService` base class that tries to standardize every possible operation. Reuse should emerge from genuinely shared behavior and stable interfaces.

### 4.5 Dependency direction

```

flowchart TB
    HTTP[HTTP Controllers]
    CONTRACTS[Input Contracts]
    APP[Application Use Cases]
    DOMAIN[Domain Rules]
    PORTS[Internal Interfaces]
    ADAPTERS[Persistence and Provider Adapters]
    DB[(PostgreSQL)]
    PROVIDERS[External Providers]

    HTTP --> CONTRACTS
    HTTP --> APP
    APP --> DOMAIN
    APP --> PORTS
    ADAPTERS -. implements .-> PORTS
    ADAPTERS --> DB
    ADAPTERS --> PROVIDERS

```

The intent is to keep business decisions independent of external providers and HTTP delivery. Rails does not need a fully abstract repository for every Active Record model; abstractions should be introduced where they create meaningful isolation, especially for external integrations and complex domain boundaries.

## 5. Strict DRY engineering standard

DRY means Don't Repeat Yourself: each business rule or authoritative piece of knowledge should have one canonical representation.

It does not mean eliminating every repeated line of code. Over-generalized abstractions can make a system harder to understand.

### 5.1 What must be centralized

- Scoring algorithms and rounding rules.
- Question-type definitions and grading behavior.
- Permission rules.
- Session lifecycle transitions.
- Attempt and deadline enforcement.
- Organization and membership access rules.
- API error conventions.
- Pagination and filtering conventions.
- Shared validation rules.
- Date and time handling.
- Event envelope definitions.
- Logging context and correlation identifiers.
- Design tokens and motion tokens.
- Integration authentication and retry policies.

### 5.2 Example: one authoritative scoring implementation

Incorrect approach:

- The frontend calculates official scores.
- The API independently calculates them.
- The leaderboard has another scoring formula.
- The report module implements its own interpretation.

Correct approach:

- The question engine defines evaluation semantics.
- The scoring module applies the approved scoring policy.
- The persisted score event records the result.
- The leaderboard and reports consume authoritative score records.
- The frontend renders the returned score.

The frontend may calculate provisional feedback for responsiveness, but the server determines the official result.

### 5.3 Shared contracts without duplicated business logic

The frontend and backend should share or generate data contracts, but not duplicate server-side authorization or trusted scoring behavior.

For example, a multiple-select response schema can be published as a versioned contract. Both sides can validate its basic structure. The backend remains authoritative for checking the correct answer and awarding points.

### 5.4 Avoid premature abstraction

Do not create a universal framework for every feature merely because two files look similar.

A good abstraction has:

1. A stable concept.
2. Multiple genuine consumers or a clear isolation benefit.
3. A well-defined interface.
4. Independent tests.
5. A measurable reduction in complexity.

Every abstraction must make future changes easier, not just reduce the number of lines.

## 6. Validation architecture

Validation must exist at every relevant trust boundary. No single Rails validation, TypeScript interface, or database constraint is sufficient on its own.

```

flowchart TD
    INPUT[User or External Input]
    EDGE[HTTP and WebSocket Boundary]
    SHAPE[Schema and Type Validation]
    AUTHZ[Authentication and Authorization]
    DOMAIN[Business Rule Validation]
    DB[Database Constraints and Transactions]
    RESULT[Validated Persisted Result]
    ERR[Structured Error Response]

    INPUT --> EDGE
    EDGE --> SHAPE
    SHAPE --> AUTHZ
    AUTHZ --> DOMAIN
    DOMAIN --> DB
    DB --> RESULT
    EDGE -. invalid .-> ERR
    SHAPE -. invalid .-> ERR
    AUTHZ -. denied .-> ERR
    DOMAIN -. rejected .-> ERR
    DB -. constraint failure .-> ERR

```

### 6.1 Validation layers

| Layer                   | What it validates                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------- |
| Browser/UI              | Required fields, immediate feedback, expected value formats.                        |
| Frontend runtime schema | Untrusted API data and user-entered payload shape.                                  |
| HTTP/API boundary       | Request structure, content type, allowed fields, size limits.                       |
| Authorization           | Whether the actor can perform the operation on that resource.                       |
| Domain                  | Whether the operation is valid in the current business state.                       |
| Active Record           | Model-level constraints and local persistence validation.                           |
| PostgreSQL              | Unique keys, foreign keys, nullability, check constraints, transactional integrity. |
| Integration boundary    | Provider responses, signatures, timeouts, payload schemas, and supported versions.  |

### 6.2 Validation rules for question types

Every question type must implement a consistent contract for:

- Definition validation.
- Response validation.
- Evaluation.
- Feedback policy.
- Score calculation.
- Maximum score.
- Schema version.
- Serialization.
- Compatibility with published historical content.

A question type should not require modifications to a giant controller or a central conditional statement every time a new type is added.

### 6.3 Validation example

A single-choice question must enforce:

- A valid question prompt.
- A valid list of unique option identifiers.
- At least two selectable options.
- A correct option that exists in the option list.
- A valid maximum score.
- A response containing an allowed option identifier.
- An eligible attempt and an open submission window.
- An authorized learner.
- No prohibited duplicate submission.

These checks should be implemented at the appropriate layers, not all placed into one large validator.

### 6.4 Validation error contract

Use machine-readable error codes and field-level details:

```
{
  "error": {
    "code": "validation_failed",
    "message": "The submitted data is invalid.",
    "request_id": "example-request-id",
    "details": {
      "options": [
        {
          "code": "duplicate_identifier",
          "message": "Option identifiers must be unique."
        }
      ]
    }
  }
}
```

The example is illustrative. Error messages must not reveal private grading information, sensitive records, or internal implementation details.

### 6.5 Validation testing

Every validation rule should have:

- A valid-input test.
- An invalid-input test.
- A boundary-condition test.
- An authorization test where relevant.
- A persistence-integrity test where relevant.
- A regression test for any previously discovered defect.

## 7. RESTful API design standard

KINGDOM Quest will expose a resource-oriented REST API. RESTfulness is not simply using HTTP verbs; it requires consistent resource identity, correct HTTP semantics, stateless request handling, predictable errors, and documented representations.

### 7.1 API conventions

- Base path: `/api/v1`.
- JSON as the standard representation.
- HTTPS for all production traffic.
- Nouns for resource paths rather than action names.
- HTTP methods that match the operation.
- Stable resource identifiers, preferably UUIDs for most domain resources.
- Consistent pagination, filtering, sorting, and error responses.
- Explicit authorization for each resource and action.
- OpenAPI documentation as the API contract.
- Backward-compatible changes within a supported API version.
- Request identifiers and idempotency where appropriate.

Use `POST` to create resources or initiate operations that are not naturally modeled as simple updates. Use `PATCH` for partial resource updates, `PUT` for complete replacement when supported, and `DELETE` for resource removal or a documented logical deletion workflow.

Not every business operation fits neatly into CRUD. A transition such as publishing an activity can be modeled as a resource representing the publication, or as an explicit command endpoint where appropriate. The design should remain predictable rather than forcing misleading CRUD semantics.

### 7.2 Resource inventory

Identity

users, profiles, sessions, password recovery

Organizations

organizations, memberships, invitations

Learning groups

classrooms, enrollments

Content

activities, activity versions, questions, question versions

Learning

assignments, attempts, responses, grade reviews

Live games

live sessions, participants, session events

Gamification

teams, achievements, score events, leaderboard snapshots

Media

media assets, upload sessions

Reporting

reports, report exports

Integrations

API clients, webhooks, webhook deliveries

Administration

audit events, platform settings

### 7.3 Authentication and user endpoints

| Method | Endpoint                             | Purpose                                                |
| ------ | ------------------------------------ | ------------------------------------------------------ |
| POST   | `/auth/email/register`               | Register an email/password user and send verification. |
| POST   | `/auth/email/verify`                  | Verify a six-digit, one-time email code and sign in.    |
| POST   | `/auth/email/resend-verification`     | Resend an email verification code.                     |
| POST   | `/auth/email/login`                   | Authenticate a verified email/password user.            |
| POST   | `/auth/password/forgot`               | Request a password reset code.                         |
| POST   | `/auth/password/reset`                | Verify the code, change password, and rotate sessions.  |
| POST   | `/auth/google_oauth2`                 | Begin Google OAuth sign-in.                            |
| DELETE | `/auth/session`                       | Revoke the current session.                            |
| GET    | `/me`                                 | Get the current user's profile.                        |
| PATCH  | `/me`                                 | Update permitted profile fields.                       |
| GET    | `/users/:id`                          | Retrieve an authorized user representation.           |
| PATCH  | `/users/:id`                          | Update permitted user fields.                          |

Email codes expire after ten minutes, allow at most five attempts, and are
issued with per-address cooldown and hourly limits. Passwords require at least
12 characters and are limited to 72 bytes for bcrypt compatibility. Password
recovery responses do not reveal whether an email address has an account.

Authentication routes may be handled by a dedicated authentication library, but the external API contract should remain consistent with the rest of the platform.

### 7.4 Organization and classroom endpoints

| Method               | Endpoint                         | Purpose                                          |
| -------------------- | -------------------------------- | ------------------------------------------------ |
| GET / POST           | `/organizations`                 | List or create organizations.                    |
| GET / PATCH / DELETE | `/organizations/:id`             | Retrieve, update, or deactivate an organization. |
| GET / POST           | `/organizations/:id/memberships` | List or create memberships.                      |
| PATCH / DELETE       | `/memberships/:id`               | Update or revoke a membership.                   |
| GET / POST           | `/organizations/:id/invitations` | List or create invitations.                      |
| GET / POST           | `/classrooms`                    | List or create authorized classrooms.            |
| GET / PATCH / DELETE | `/classrooms/:id`                | Manage a classroom.                              |
| GET / POST           | `/classrooms/:id/enrollments`    | List or create enrollments.                      |
| DELETE               | `/enrollments/:id`               | Remove an enrollment.                            |

Creation and update endpoints must enforce organization ownership and the actor's role. A user must never gain access to another organization's records by changing an identifier.

### 7.5 Activity and question endpoints

| Method               | Endpoint                               | Purpose                                             |
| -------------------- | -------------------------------------- | --------------------------------------------------- |
| GET / POST           | `/activities`                          | List or create activities.                          |
| GET / PATCH / DELETE | `/activities/:id`                      | Retrieve, edit, or archive an activity.             |
| GET / POST           | `/activities/:id/versions`             | List or create versions.                            |
| GET                  | `/activities/:id/versions/:version_id` | Retrieve a specific version.                        |
| POST                 | `/activities/:id/publications`         | Publish a validated version.                        |
| POST                 | `/activities/:id/duplications`         | Duplicate an activity.                              |
| GET / POST           | `/activities/:id/questions`            | List or add questions to a draft.                   |
| GET / PATCH / DELETE | `/questions/:id`                       | Manage an editable question.                        |
| GET / POST           | `/questions/:id/versions`              | Retrieve or create question versions.               |
| POST                 | `/activities/:id/previews`             | Create a preview representation or preview session. |

Publishing should create a publication record or equivalent auditable state transition. Published content must not be silently edited in place.

### 7.6 Assignment and assessment endpoints

| Method               | Endpoint                       | Purpose                                        |
| -------------------- | ------------------------------ | ---------------------------------------------- |
| GET / POST           | `/assignments`                 | List or create assignments.                    |
| GET / PATCH / DELETE | `/assignments/:id`             | Manage an authorized assignment.               |
| GET / POST           | `/assignments/:id/attempts`    | List or initiate attempts, subject to policy.  |
| GET                  | `/attempts/:id`                | Retrieve an authorized attempt.                |
| GET / POST           | `/attempts/:id/responses`      | List permitted responses or submit a response. |
| GET / PATCH          | `/responses/:id`               | Retrieve or revise a response when allowed.    |
| POST                 | `/attempts/:id/submissions`    | Finalize an attempt.                           |
| GET                  | `/attempts/:id/results`        | Retrieve permitted results.                    |
| GET / POST           | `/responses/:id/grade-reviews` | Retrieve or create a grade review.             |

Do not expose correct answers merely because the learner can retrieve an attempt. Answer visibility must follow the activity's feedback and release policies.

### 7.7 Live-session endpoints

| Method     | Endpoint                          | Purpose                                                              |
| ---------- | --------------------------------- | -------------------------------------------------------------------- |
| GET / POST | `/live-sessions`                  | List or create live sessions.                                        |
| GET        | `/live-sessions/:id`              | Retrieve current authorized state.                                   |
| POST       | `/live-sessions/:id/participants` | Join or register participation using a validated joining credential. |
| GET        | `/live-sessions/:id/participants` | List permitted participants.                                         |
| POST       | `/live-sessions/:id/starts`       | Start the session.                                                   |
| POST       | `/live-sessions/:id/pauses`       | Pause the session.                                                   |
| POST       | `/live-sessions/:id/resumptions`  | Resume the session.                                                  |
| POST       | `/live-sessions/:id/advancements` | Advance the session.                                                 |
| POST       | `/live-sessions/:id/completions`  | Complete the session.                                                |
| GET        | `/live-sessions/:id/events`       | Retrieve an authorized event history or recovery window.             |
| GET        | `/live-sessions/:id/results`      | Retrieve authorized results.                                         |

The plural action-resource patterns shown here are one viable REST-oriented approach for lifecycle transitions. The team should select a consistent convention and document it in an ADR before implementation. Avoid mixing arbitrary verb endpoints with resource endpoints.

### 7.8 Gamification and reporting endpoints

| Method     | Endpoint                  | Purpose                                                 |
| ---------- | ------------------------- | ------------------------------------------------------- |
| GET        | `/leaderboards`           | Retrieve a permitted leaderboard.                       |
| GET        | `/users/:id/achievements` | Retrieve visible achievements.                          |
| GET        | `/teams/:id`              | Retrieve an authorized team.                            |
| GET / POST | `/reports`                | List or request reports.                                |
| GET        | `/reports/:id`            | Retrieve a report.                                      |
| POST       | `/report-exports`         | Request an export.                                      |
| GET        | `/report-exports/:id`     | Retrieve export status and an authorized download link. |

Expensive reports should be asynchronous. The client creates an export request, polls its resource or receives a notification, and downloads the completed artifact through an authorized, short-lived link.

### 7.9 Standard query parameters

Support a consistent subset where relevant:

- `page` and `per_page` for pagination.
- `sort` for supported sort keys.
- `filter[status]` and other explicitly supported filters.
- `include` only for documented related resources.
- `fields` only if sparse fieldsets provide meaningful value.
- `created_after` and `created_before` for supported date-filtered resources.

Enforce maximum page sizes, allowed sort fields, and query complexity limits. Never interpolate user-supplied sort or column names directly into SQL.

For very large or frequently changing collections, cursor pagination may be preferable to page-number pagination.

### 7.10 Idempotency, concurrency, and caching

- Support idempotency keys for retriable creation or submission operations where duplicate effects would be harmful.
- Define the key's scope, expiration, and behavior for a reused key with a different payload.
- Use conditional requests, version fields, or locking for concurrent edits.
- Use `ETag` and `If-Match` where useful for editable resources.
- Use cache headers according to data sensitivity and freshness requirements.
- Do not cache private learner results publicly.
- Ensure retries cannot award duplicate points or create duplicate grade records.

### 7.11 OpenAPI as the contract

The REST API should have a maintained OpenAPI specification.

The pipeline should verify that:

1. Every public endpoint is documented.
2. Request and response schemas match implementation.
3. Error responses follow the common contract.
4. Authentication requirements are declared.
5. Breaking changes are detected.
6. TypeScript client types are generated or checked against the contract.
7. Examples reflect valid payloads.

Generated TypeScript types improve consistency but do not replace runtime validation of untrusted network data.

## 8. Product domains and feature requirements

### 8.1 Identity and organizations

Support learner, educator, organization administrator, and platform administrator roles, with permissions scoped to the appropriate organization and resource.

Core features:

- Email registration with a six-digit, expiring verification code before the
  account can sign in.
- Email and password sign-in, with Google OAuth available as an alternative.
- Password recovery through a separate, expiring one-time email code; responses
  must not reveal whether an email/password account exists.
- Resend cooldowns, attempt limits, and rate limits for authentication codes
  and password sign-in.
- Revocable sessions in secure, HTTP-only cookies; password recovery revokes
  existing sessions before establishing the new session.
- Profile management.
- Organization invitations.
- Membership and role management.
- Classroom creation.
- Enrollment and removal.
- Account suspension and recovery.
- Account export and deletion workflows.

Authorization must be explicit. A platform administrator's privileges must not automatically be granted to organization administrators.

### 8.2 Activity and content management

Educators must be able to:

- Create an activity.
- Add and reorder questions.
- Preview questions as a learner.
- Save drafts.
- Publish immutable versions.
- Duplicate existing activities.
- Organize content into libraries or folders.
- Archive content.
- Assign published versions.
- Reuse existing questions where permitted.

The content domain owns content lifecycle and versioning. It should not own the live-session lifecycle or implement scoring independently.

### 8.3 Question engine

Support a registry of question types with a stable interface.

## Initial question-type catalogue

1\. Single choice

Exactly one option may be selected.

2\. Multiple select

One or more options may be selected, with configurable scoring.

3\. True or false

Binary response with optional explanation.

4\. Short answer

Text response with controlled automatic grading or manual review.

5\. Fill in the blank

One or more blanks with accepted answer variants.

6\. Matching

Match items across two or more groups.

7\. Ordering

Arrange items into a defined sequence.

8\. Numeric response

Numeric answer with configurable tolerance.

9\. Poll

Collect responses without necessarily grading them.

10\. Image-based question

Answer using an image, diagram, or visual prompt.

11\. Audio or video prompt

Answer questions based on accessible media.

12\. Essay

Long-form response with rubric-based grading.

13\. Code response

A future sandboxed programming exercise.

Each type should declare its own definition schema, response schema, evaluation strategy, feedback behavior, maximum score, and compatibility rules.

### Per-question timing

- New questions default to 30 seconds. Educators may set an individual limit from 5 to 300 seconds or turn the timer off (`0`) for that question.
- The published activity version freezes each question's time limit, so later changes cannot alter an active or already-published quest.
- The API starts a play session and records each response in question order. The server decides whether the deadline has elapsed; a browser countdown is only a display.
- A timed-out question is recorded as unanswered, earns zero points, and advances to the next question. A late answer cannot override the timeout.
- The client retries session and answer requests with idempotency keys. A completed answer cannot be changed or submitted twice.
- Immediate feedback may identify whether the submitted answer was correct, but the response does not expose answer identifiers for unanswered questions. Final answer visibility follows the activity's result policy.
- Sessions expire after one hour; expired session records are purged after a short retry/retention window.
- The untimed setting is required as an accessibility alternative to fixed deadlines. Any future timed mode must preserve a way to turn off or adjust its limit.

New types should be addable without rewriting the assessment workflow. Some question types, especially essay and code response, require dedicated grading or sandboxing capabilities and should not be treated as simple extensions of multiple-choice scoring.

### 8.4 Game modes

- Teacher-paced live game: the educator controls question progression.
- Student-paced activity: learners progress independently within assignment policies.
- Timed challenge: a question or activity has a configured deadline.
- Team competition: scoring and progression can operate at team level.
- Practice mode: learners receive immediate feedback and can retry under defined rules.
- Assessment mode: feedback and answer visibility follow assessment policies.
- Poll mode: the activity collects opinions or responses without a correct answer.
- Tournament mode: a later-stage feature with rounds, qualification, and controlled ranking.

Game modes should be represented by explicit configuration and policy objects. Avoid creating a separate, duplicated implementation of the question engine for every mode.

### 8.5 Scoring and fairness

Scoring policies must specify:

- Correctness rules.
- Partial-credit behavior.
- Maximum score.
- Negative marking, if explicitly enabled.
- Speed bonuses, if enabled.
- Retry behavior.
- Team score aggregation.
- Tie-breaking.
- Rounding.
- Feedback and answer-release rules.

Speed should never be mandatory as a scoring factor. Educators should be able to disable speed bonuses and use mastery-oriented scoring.

### 8.6 Group play, scoring, and rankings

KINGDOM Quest supports two distinct group-play modes, selected by the host when publishing a quest:

- **Participant-paced:** Each learner starts and completes an independent attempt. Scores feed a shared provisional leaderboard as participants finish; the leaderboard is not presented as final while the activity remains open.
- **Host-paced live room:** A host creates a room with its own join code and direct link. Participants join the waiting room as guests or signed-in users. The host starts the room and controls each question transition and the end of the game. Every participant sees the same question index and server start time.

Live-room participant answers are recorded independently against the shared round deadline. Advancing a round records zero for any participant who has not answered, then starts the next question for all participants. The host must be authorized as the room owner for state-changing host commands. Guest participants receive unguessable session identifiers; room codes are for joining, not authorization. Production release requires abuse controls, retention policy, authenticated host roles, and real-time delivery/authorization review.

The default speed policy is proportional and server-authoritative:

`award = base_points + round(base_points * max(0, 1 - elapsed_seconds / time_limit_seconds))`

This applies only to correct answers on timed questions when speed scoring is enabled. It awards the configured base at the deadline and up to a 100% speed bonus for a near-immediate answer. Untimed questions award base points only; incorrect and timed-out answers award zero. The server measures elapsed time and calculates the score; clients cannot submit a claimed score or response time. Educators can disable speed scoring. The displayed maximum for a question is twice its configured points only when it has a timer and speed scoring is enabled.

Rankings sort by total points descending, then cumulative server-recorded answer time ascending, then display name as a stable final tie-break. Completed participant-paced attempts contribute to a provisional leaderboard. Host-paced room standings include current persisted scores and become final only after the host ends the last round. Results show the top three in a visual podium, with first place centered; rankings remain available below the podium. A ranking is not a substitute for reporting correctness and learning progress.

Joining supports a six-character uppercase letter-and-number code and a direct `/join/{code}` link, which resolves to either a participant-paced activity or a live room. Codes omit ambiguous characters (`I`, `O`, `0`, and `1`). The six-character migration rotates previously issued codes, so hosts must share updated links/codes after deployment. After resolving the code, a learner chooses a display name and may change it until their active live round is answered (or until a self-paced attempt is complete). Guest play does not require an account; Google sign-in is an optional choice and must not block guest access.

### Production deployment

Launchpad deploys the SvelteKit web application and Rails API as separate
services on the same domain. The web service owns `/`; Rails owns `/api/`.
Production Rails migrations run with `db:prepare` before the API starts.
Configure `DATABASE_URL` in Launchpad; optional `CACHE_DATABASE_URL`,
`QUEUE_DATABASE_URL`, and `CABLE_DATABASE_URL` values can point Rails' auxiliary
database roles at dedicated databases. Without them, those roles use
`DATABASE_URL`.

Set `WEB_APP_URL` to the HTTPS application origin and
`GOOGLE_REDIRECT_URI` to
`https://<application-domain>/api/v1/auth/google_oauth2/callback`. The
corresponding callback URL must also be authorized in the Google OAuth client.
Production secrets remain in Launchpad's environment store.

### 8.7 Question authoring, import, and shuffle

- An activity supports 1–100 single-choice questions.
- Educators may author questions in the editor or import a CSV/XLSX workbook. Imported questions are parsed locally, capped at 5 MB and 100 rows, validated against the same question limits, and added to the editor for review and correction before publishing. Import never publishes content directly.
- The CSV/XLSX first row uses these case-insensitive columns: `question`, `option_a`, `option_b`, optional contiguous `option_c` through `option_f`, `correct_answer`, optional `points`, and optional `time_limit_seconds`. `correct_answer` is either an option letter or an exact answer label. Points default to 100 and timers default to 30 seconds; `0` means untimed. A downloadable CSV example is included in the web app.
- Hosts may request shuffled question order. The order is randomized once while building the immutable published version, not on each browser refresh or between participants; question IDs, answer choices, and correct-answer mapping stay attached.

The first implementation polls room state over REST and uses database-backed timestamps and records for correctness. Action Cable or another authenticated push transport can replace polling without changing the room state machine or scoring authority.

## 9. Database design and data integrity

PostgreSQL is the authoritative persistence layer. The database must protect important invariants independently of the API.

### 9.1 Core entity relationships

```

erDiagram
    USERS ||--o{ MEMBERSHIPS : has
    ORGANIZATIONS ||--o{ MEMBERSHIPS : includes
    ORGANIZATIONS ||--o{ CLASSROOMS : owns
    CLASSROOMS ||--o{ ENROLLMENTS : has
    USERS ||--o{ ENROLLMENTS : joins
    USERS ||--o{ ACTIVITIES : authors
    ACTIVITIES ||--o{ ACTIVITY_VERSIONS : versions
    ACTIVITY_VERSIONS ||--o{ QUESTION_VERSIONS : contains
    QUESTIONS ||--o{ QUESTION_VERSIONS : versions
    ACTIVITY_VERSIONS ||--o{ ASSIGNMENTS : assigned
    ASSIGNMENTS ||--o{ ATTEMPTS : receives
    USERS ||--o{ ATTEMPTS : starts
    ATTEMPTS ||--o{ RESPONSES : contains
    QUESTION_VERSIONS ||--o{ RESPONSES : answered
    USERS ||--o{ LIVE_SESSIONS : hosts
    LIVE_SESSIONS ||--o{ SESSION_PARTICIPANTS : includes
    LIVE_SESSIONS ||--o{ SESSION_EVENTS : records
    USERS ||--o{ SESSION_PARTICIPANTS : joins
    USERS ||--o{ SCORE_EVENTS : earns
    USERS ||--o{ AUDIT_EVENTS : performs

```

### 9.2 Proposed tables

| Domain        | Tables                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------- |
| Identity      | `users`, authentication/session records                                                           |
| Organizations | `organizations`, `memberships`, `invitations`                                                     |
| Classrooms    | `classrooms`, `enrollments`                                                                       |
| Activities    | `activities`, `activity_versions`, `questions`, `question_versions`, `publications`               |
| Assignments   | `assignments`, `attempts`, `responses`, `grade_reviews`                                           |
| Live sessions | `live_sessions`, `session_participants`, `session_events`                                         |
| Gamification  | `teams`, `team_memberships`, `score_events`, `achievements`, `learner_achievements`               |
| Media         | `media_assets`, upload records                                                                    |
| Integrations  | `api_clients`, `webhook_endpoints`, `webhook_deliveries`, provider-specific configuration records |
| Operations    | `audit_events`, `outbox_events`, idempotency records, export jobs                                 |

The table inventory is a starting point. Each table should be introduced when its domain and lifecycle are defined.

### 9.3 Data modeling rules

- Use foreign keys and unique constraints.
- Define nullability intentionally.
- Use `jsonb` for variable question definitions and configuration.
- Use relational tables for stable relationships and queryable business entities.
- Store timestamps consistently in UTC.
- Use transactions for multi-record business operations.
- Index foreign keys and demonstrated query patterns.
- Prefer explicit status fields and documented state transitions.
- Use soft deletion only where business or legal requirements justify it.
- Preserve immutable published content.
- Avoid unbounded JSON blobs that mix unrelated domain state.

### 9.4 Question versioning

A published question must be reproducible.

Each response references the precise question version presented to the learner. An attempt references the activity version or publication used for that attempt.

When an educator edits a published activity, the platform creates a new version. Existing submissions remain associated with the original version.

### 9.5 Score integrity

Official score changes should be auditable. A score event should identify its source, the applicable scoring policy version, the points awarded, and the reason for any adjustment.

Prevent duplicate scoring using a database uniqueness rule or an equivalent durable idempotency mechanism. Recalculating a leaderboard must not award points again.

### 9.6 Database migration policy

Every schema change must:

1. Be committed as a reviewed migration.
2. Be tested against the supported database version.
3. Preserve existing data unless a documented transformation is required.
4. Avoid long table locks where practical.
5. Support safe deployment sequencing.
6. Include a recovery strategy.
7. Update schema documentation and tests.

For incompatible changes, use an expand-and-contract process: add the new structure, deploy compatible code, migrate data, switch consumers, and only then remove the old structure.

## 10. Real-time sessions and event processing

### 10.1 Separate commands from notifications

A teacher action is a command that changes authoritative state. A WebSocket event informs connected clients that a change occurred.

For example:

1. The teacher submits a request to publish the next question.
2. Rails validates authorization and the session's current state.
3. The database transaction updates the session and records the event.
4. The event is delivered to connected participants.
5. Learners update their interfaces.
6. Submissions are validated and persisted through the server.
7. The teacher sees updated participation and results.

### 10.2 Session state machine

Define allowed transitions explicitly:

```

stateDiagram-v2
    [*] --> Draft
    Draft --> Waiting: Publish lobby
    Waiting --> Active: Start
    Active --> Paused: Pause
    Paused --> Active: Resume
    Active --> Completed: Finish
    Paused --> Completed: Finish
    Completed --> [*]

```

A closed session should not become active again accidentally. If restarting or replaying a session is supported, it should be a separately authorized operation with clearly defined historical consequences.

### 10.3 Reliable event delivery

Use a durable event record or transactional outbox when publishing events must reliably follow a committed database change.

A background worker can publish pending events and mark them delivered. Delivery may be retried, so consumers must tolerate duplicates.

The platform must not broadcast a success event before the corresponding database transaction commits.

### 10.4 Scaling real-time delivery

Start with Action Cable and a deployment configuration suitable for the expected connection count. Load-test before choosing additional infrastructure.

Redis pub/sub may be appropriate for coordinating WebSocket delivery across multiple application instances. Redis is not the authoritative store for accepted answers or grades.

A Go-based real-time service is a possible later optimization, but it should be introduced only when the measured requirements justify a separate service, deployment pipeline, protocol contract, and operational burden.

## 11. Integration architecture

Easy integration is a first-class requirement. KINGDOM Quest should be able to connect to external learning systems, identity providers, notification services, AI providers, and reporting systems without scattering provider-specific code throughout the application.

### 11.1 Integration layers

```

flowchart TB
    DOMAIN[Core Domain Modules]
    PORT[Integration Interfaces]
    ADAPTER[Provider Adapters]
    AUTH[Credential and Secret Management]
    WEBHOOK[Webhook Ingress and Egress]
    JOB[Async Delivery and Retry]
    PROVIDER[External Services]

    DOMAIN --> PORT
    PORT --> ADAPTER
    ADAPTER --> AUTH
    ADAPTER --> PROVIDER
    PROVIDER --> WEBHOOK
    WEBHOOK --> ADAPTER
    ADAPTER --> JOB
    JOB --> PROVIDER

```

The domain should depend on a stable internal contract, not on a provider's SDK or response format.

### 11.2 Initial integration categories

- Email delivery.
- File and media storage.
- Identity and single sign-on.
- AI-assisted content creation.
- Learning Management Systems (LMS).
- Analytics and reporting exports.
- Webhooks for partner systems.
- Future payments or subscription billing if the product requires it.

### 11.3 Adapter contract

Each provider adapter should define:

- Supported operations.
- Input and output schemas.
- Authentication method.
- Timeouts.
- Retryable versus permanent errors.
- Rate-limit behavior.
- Idempotency behavior.
- Logging and observability.
- Provider-specific configuration.
- Contract tests.

A provider should be replaceable without rewriting the learning, scoring, or assignment domain.

### 11.4 Webhook security and reliability

For outbound webhooks:

- Sign payloads with a per-endpoint secret.
- Include a unique event ID and timestamp.
- Retry transient failures with bounded exponential backoff and jitter.
- Record delivery attempts and response outcomes.
- Support endpoint suspension after persistent failure.
- Provide a way to inspect and replay eligible failed deliveries.

For inbound webhooks:

- Verify signatures before processing.
- Enforce timestamp and replay protection where supported.
- Deduplicate event IDs.
- Validate payload schemas.
- Apply rate limits.
- Never trust provider-supplied resource identifiers without authorization and ownership checks.

### 11.5 Public API and partner access

If partners need programmatic access, introduce a dedicated API-client model with:

- Explicit scopes.
- Credential rotation and revocation.
- Rate limits.
- Audit records.
- Organization-level restrictions.
- Documented API versions.
- Sandbox credentials where appropriate.

Do not reuse human session cookies as integration credentials.

## 12. Frontend modularity, design system, and animations

### 12.1 Feature-oriented SvelteKit design

Each substantial frontend feature should own its components, state, validation schemas, and API interactions.

For example:

```

src/lib/features/questions/
├── components/
│   ├── QuestionRenderer.svelte
│   ├── QuestionPrompt.svelte
│   ├── AnswerFeedback.svelte
│   └── QuestionProgress.svelte
├── types/
│   └── question.ts
├── schemas/
│   └── question-response.ts
├── state/
│   └── question-player.svelte.ts
├── api/
│   └── question-client.ts
├── utils/
│   └── response-normalizer.ts
├── tests/
│   ├── renderer.test.ts
│   └── response-validation.test.ts
└── index.ts

```

This is illustrative. The exact store conventions should follow the selected Svelte version. The important requirements are cohesive ownership, minimal cross-feature coupling, and explicit public exports.

Avoid a single `utils.ts`, `types.ts`, or `components.ts` file that grows to contain the entire application.

### 12.2 Reusable design-system components

Build shared components for:

- Buttons, inputs, selects, dialogs, menus, and tooltips.
- Cards, badges, tabs, and navigation.
- Loading indicators and skeletons.
- Empty, success, warning, and error states.
- Question containers and response controls.
- Progress indicators and score summaries.
- Timers, leaderboards, and session status.

The shared UI layer should handle presentation and accessibility. It should not know how a particular question is graded.

### 12.3 Brand and motion tokens

Use the EKD Digital palette:

- Charcoal: `#1F1C18`
- Gold: `#C8A061`
- Light gold: `#D4AF6A`
- Deep red: `#8E0E00`
- Navy: `#182E5F`
- Ivory: `#FDF9F2`
- Black: `#1A1A1A`

Keep most screens to three or four brand colors, while retaining functional status colors where needed for accessibility.

Define motion tokens for quick interactions, normal transitions, and optional celebrations. Use Svelte transitions and CSS for most effects, introducing Motion or more advanced rendering only where the experience justifies it.

### 12.4 Motion behavior

- Answer selection: immediate, subtle feedback.
- Question navigation: smooth transition with stable layout.
- Correct answer: clear confirmation and optional celebration.
- Incorrect answer: helpful feedback without shaming.
- Progress: animated indicator with an accessible text equivalent.
- Leaderboard: restrained movement when rankings change.
- Disconnection: persistent status indicator and recovery information.
- Reduced motion: eliminate nonessential movement without removing essential feedback.

Animations must never be the only way to communicate correctness, urgency, or status.

### 12.5 Performance and accessibility

- Follow WCAG 2.2 AA as the baseline.
- Support keyboard-only use and screen readers.
- Respect `prefers-reduced-motion`.
- Make per-question countdowns visible and understandable without announcing every second to screen readers; offer untimed questions.
- Start audio only after the learner explicitly starts a quest, expose an immediate sound on/off control, and keep all correctness feedback available visually.
- Stop or fade ambient audio when a quest ends or the player leaves. Audio load failures must not prevent gameplay.
- Use original, locally generated audio cues. Keep the ambient pad quiet, ticks restrained to the final five seconds, the correct-answer chord warm, and the incorrect-answer cue soft.
- Keep question rendering lightweight.
- Lazy-load large media.
- Avoid unnecessary JavaScript in the learner player.
- Test on mobile devices and slow connections.
- Target good Core Web Vitals at the 75th percentile.
- Monitor real-world performance after launch.

### 12.6 Audio implementation references

- Howler.js documents client-side `Howl` playback, looping, volume, fades, and cleanup: <https://github.com/goldfire/howler.js#documentation>.
- Svelte's `onMount` lifecycle does not run during server-side rendering and supports synchronous cleanup callbacks: <https://svelte.dev/docs/svelte/lifecycle-hooks>.
- WCAG 2.2 Success Criterion 1.4.2 requires a way to pause/stop or independently control automatically playing audio longer than three seconds: <https://www.w3.org/WAI/WCAG22/Understanding/audio-control.html>.
- WCAG 2.2 Success Criterion 2.2.1 describes turning off, adjusting, or extending time limits where possible: <https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html>.

## 13. Software Development Life Cycle (SDLC)

SDLC is a mandatory part of the architecture, not documentation to write after development. Every feature must pass through requirements, design, implementation, verification, release, and maintenance.

KINGDOM Quest should use an iterative, Agile-inspired workflow with formal engineering gates for security, architecture, data integrity, and production releases.

### 13.1 SDLC lifecycle

```

flowchart TD
    REQ[Requirements and Acceptance Criteria]
    DESIGN[Architecture and Technical Design]
    PLAN[Task Breakdown and Estimation]
    DEV[Implementation]
    REVIEW[Code Review and Static Analysis]
    TEST[Automated and Manual Testing]
    SEC[Security and Accessibility Checks]
    RELEASE[Staging and Release Approval]
    DEPLOY[Production Deployment]
    MONITOR[Monitoring and Feedback]
    IMPROVE[Maintenance and Improvement]

    REQ --> DESIGN
    DESIGN --> PLAN
    PLAN --> DEV
    DEV --> REVIEW
    REVIEW --> TEST
    TEST --> SEC
    SEC --> RELEASE
    RELEASE --> DEPLOY
    DEPLOY --> MONITOR
    MONITOR --> IMPROVE
    IMPROVE --> REQ

```

### 13.2 Stage 1: requirements engineering

Before implementation, define:

- Business objective.
- User roles and permissions.
- User journey.
- Functional requirements.
- Non-functional requirements.
- Data ownership and retention.
- Failure scenarios.
- Acceptance criteria.
- Dependencies and risks.
- Accessibility requirements.
- API and integration implications.

Every feature should have testable acceptance criteria. Statements such as "the live game must be fast" are insufficient without measurable expectations and a defined test environment.

Example:

Requirement: A learner can submit an answer to an active question.

Acceptance criteria:

1. The learner is authorized to participate.
2. The question belongs to the active session.
3. The submission window is open.
4. The response matches the question's response schema.
5. The submission is persisted exactly once.
6. The learner receives a clear result or accepted-submission state.
7. A retry does not award duplicate points.
8. Unauthorized or late submissions are rejected consistently.
9. The operation produces appropriate audit or diagnostic information.

### 13.3 Stage 2: architecture and technical design

Before coding a significant feature, document:

- Module ownership.
- Public interfaces.
- Data model changes.
- API routes and schemas.
- Authorization rules.
- State transitions.
- Transaction boundaries.
- Events and background jobs.
- Error handling.
- Observability.
- Test strategy.
- Rollback or recovery considerations.

Use Architecture Decision Records when a decision has long-term consequences, such as authentication, question versioning, tenancy, event delivery, or a new external integration.

### 13.4 Stage 3: task breakdown

Break each feature into small, reviewable work items.

A feature may produce separate tasks for:

1. Database migration.
2. Domain contract.
3. Application service.
4. Authorization policy.
5. API endpoint.
6. API documentation.
7. Frontend integration.
8. Tests.
9. Monitoring.
10. Documentation.

Do not create a separate file or task for every trivial line of code. The objective is independently reviewable responsibilities and manageable changes, not unnecessary fragmentation.

### 13.5 Stage 4: implementation standards

Every implementation must follow these rules:

- Small, cohesive files.
- Explicit public interfaces.
- Consistent naming conventions.
- Strong input validation.
- No business logic in controllers.
- No duplicated scoring or authorization logic.
- No hidden cross-module dependencies.
- No hardcoded secrets.
- No undocumented public API changes.
- No unreviewed production database mutations.
- No swallowing exceptions without a defined recovery strategy.
- No unbounded retries for external operations.

### 13.6 Stage 5: code review

Every pull request should be reviewed for:

- Correctness and acceptance criteria.
- Modularity and dependency direction.
- DRY compliance without over-abstraction.
- Security and authorization.
- Input validation.
- Database integrity.
- REST API consistency.
- Test coverage.
- Performance implications.
- Accessibility.
- Documentation and observability.

A reviewer should be able to understand the change without reading an entire domain's implementation.

### 13.7 Stage 6: verification

Automated checks should run continuously, not only before release.

| Test category | Main purpose                                                       |
| ------------- | ------------------------------------------------------------------ |
| Unit          | Verify isolated domain rules and calculations.                     |
| Integration   | Verify collaboration between services, models, and the database.   |
| Request/API   | Verify REST semantics, contracts, status codes, and authorization. |
| Contract      | Verify compatibility between API producers and consumers.          |
| Architecture  | Detect forbidden dependencies and boundary violations.             |
| End-to-end    | Verify complete user journeys.                                     |
| Security      | Detect vulnerabilities and unauthorized access.                    |
| Accessibility | Verify keyboard, screen-reader, contrast, and motion requirements. |
| Performance   | Measure response latency, throughput, and resource consumption.    |
| Resilience    | Verify retries, recovery, timeouts, and partial failures.          |

### 13.8 Stage 7: release and deployment

Every release must have:

- A reviewed release scope.
- Passing required CI checks.
- Approved database migrations.
- Updated API documentation.
- A rollback or roll-forward plan.
- Staging verification.
- A production smoke test.
- Monitoring and alerting.
- A clear owner for release decisions.

For sensitive changes to authentication, grading, or permissions, require additional security review.

### 13.9 Stage 8: maintenance

After release:

- Monitor error rates and latency.
- Review failed jobs and webhook deliveries.
- Investigate user-reported issues.
- Patch dependencies.
- Review database query performance.
- Remove obsolete feature flags and deprecated contracts.
- Update operational documentation.
- Add regression tests for discovered defects.

A defect is not fully resolved until the underlying failure is understood and an appropriate regression test exists, where feasible.

## 14. Coding standards and architecture enforcement

Architecture rules are only useful if the repository can detect violations automatically.

### 14.1 Ruby and Rails

Use:

- RuboCop with agreed Ruby and Rails rules.
- Standard Rails naming and autoloading conventions.
- Focused service and query objects.
- Explicit domain error types.
- Database constraints for critical invariants.
- Consistent transaction boundaries.
- RSpec or Rails' supported testing stack, chosen once for the project.
- Dependency and security auditing.

Do not introduce multiple overlapping testing frameworks without a clear reason.

### 14.2 TypeScript and SvelteKit

Use:

- Strict TypeScript settings.
- ESLint and Prettier, or an agreed equivalent.
- Svelte accessibility diagnostics.
- Runtime validation for untrusted data.
- Generated API types where practical.
- Feature-level component tests.
- Consistent API error handling.
- Explicit loading and error states.

TypeScript's compile-time types do not validate HTTP responses at runtime.

### 14.3 Architectural tests

Automate checks for:

- Controllers not containing domain workflows.
- No circular module dependencies.
- Cross-domain access occurring through approved interfaces.
- No direct provider SDK calls from domain logic.
- No imports from private frontend feature paths.
- No direct database access from SvelteKit browser code.
- No hardcoded credentials.
- Required tests for public endpoints and critical domain operations.
- No undocumented API breaking changes.

Tools such as dependency-graph analyzers and custom lint rules can enforce some of these boundaries. Not every rule needs a custom tool on day one; start with the highest-risk constraints and expand as the codebase grows.

### 14.4 Pull request template

Every pull request should answer:

- What problem does this solve?
- Which requirements does it satisfy?
- Which modules and public interfaces change?
- Does it introduce or alter API contracts?
- Does it change the database?
- What validation and authorization checks are included?
- What tests were added or run?
- Are there performance, accessibility, or security implications?
- How will the change be deployed and recovered if necessary?

## 15. Security and privacy requirements

Security is a platform-wide responsibility. No module may assume that another layer has already performed every necessary check.

### 15.1 Authentication and authorization

- Use a maintained authentication library appropriate to Rails.
- Protect cookie-authenticated state-changing requests against CSRF.
- Use secure, HTTP-only cookies with appropriate `SameSite` and `Secure` settings.
- Hash passwords with a modern password-hashing algorithm.
- Rate-limit authentication, password recovery, joining codes, and sensitive operations.
- Support session revocation and account suspension.
- Enforce authorization on every protected API request and WebSocket subscription.
- Scope database queries to the appropriate organization and resource.
- Separate platform administration from organization-level permissions.

### 15.2 Assessment integrity

- Keep answer keys out of unauthorized learner responses.
- Validate all submissions on the server.
- Enforce attempt limits and deadlines on the server.
- Prevent duplicate submissions and duplicate scoring.
- Record manual grade changes.
- Preserve published question and activity versions.
- Apply consistent rules for reopening, resubmission, and late work.

### 15.3 Integration security

- Store credentials in protected configuration or a secrets manager.
- Rotate and revoke integration credentials.
- Verify inbound webhook signatures.
- Restrict outbound webhook destinations to mitigate SSRF and misuse.
- Apply provider-specific rate limits.
- Validate provider responses.
- Never expose privileged integration credentials to the browser.

### 15.4 Privacy and governance

Establish documented rules for:

- Learner data collection and purpose limitation.
- Data access and export.
- Account deletion and retention.
- Media retention.
- Audit log retention.
- AI provider data handling.
- Consent and guardian requirements where applicable.
- Organization-level reporting permissions.
- Data residency where required.

Because learners may be minors, applicable education and privacy requirements must be assessed for each target market before launch.

### 15.5 Security testing

Use relevant OWASP guidance and automate dependency scanning, secret detection, static analysis, and vulnerability testing.

Explicitly test:

- Cross-organization data access.
- Unauthorized grade modification.
- Joining-code brute force.
- WebSocket authorization.
- Upload validation.
- Authentication abuse.
- Insecure direct object references.
- Replay attacks on integrations.
- Exposure of answer keys.
- Privilege escalation.

## 16. Testing and quality strategy

Testing must follow the modular architecture. Each domain owns its own tests, while integration tests verify its collaboration with other modules.

### 16.1 Required coverage

| Layer                      | Examples                                                     |
| -------------------------- | ------------------------------------------------------------ |
| Domain unit tests          | Scoring, question validation, permission decisions.          |
| Application tests          | Publishing, attempt creation, session transitions.           |
| Database integration tests | Constraints, transactions, uniqueness, locking.              |
| API request tests          | Status codes, schemas, pagination, error responses.          |
| Contract tests             | OpenAPI compatibility and provider payloads.                 |
| Frontend component tests   | Question interactions, forms, feedback, accessible controls. |
| End-to-end tests           | Educator creates activity; learner completes it.             |
| Load tests                 | Concurrent sessions and simultaneous submissions.            |
| Security tests             | Tenant isolation, authorization, credential handling.        |
| Resilience tests           | Worker restarts, retries, reconnection, partial outages.     |

### 16.2 Concurrency testing

Simulate two or more requests attempting to submit the same answer, publish the same activity version, or award points for the same event.

Verify that:

- Exactly one permitted submission is accepted when the policy allows one.
- Duplicate retries return a consistent outcome.
- No score is awarded twice.
- Session transitions cannot be applied in invalid order.
- Database constraints remain effective under concurrent access.

### 16.3 Initial capacity testing

Test 100 participants in one session, 500 participants across sessions, and a larger scenario of 1,000 or more concurrent connections as an early scalability exercise.

Measure actual results rather than assuming the application meets these targets. Include submission bursts, reconnect storms, worker delays, and database contention.

### 16.4 Accessibility and user testing

Run automated checks alongside manual keyboard and screen-reader testing. Include reduced-motion behavior, mobile layouts, low-bandwidth conditions, and understandable feedback for incorrect answers.

Test with educators and learners before general release. Product usability cannot be established by automated tests alone.

## 17. Deployment, CI/CD, and operations

### 17.1 Deployment topology

Start with separate web, API, and worker processes. Keep the codebase modular, but avoid operating unnecessary distributed services.

```

flowchart TB
    CLIENT[Browser and Mobile Web]
    EDGE[CDN and TLS Proxy]
    WEB[SvelteKit]
    API[Rails API and Action Cable]
    WORKER[Background Workers]
    DB[(PostgreSQL)]
    STORAGE[Object Storage]
    MON[Monitoring and Logging]

    CLIENT --> EDGE
    EDGE --> WEB
    EDGE --> API
    API --> DB
    API --> STORAGE
    API --> WORKER
    WORKER --> DB
    WORKER --> STORAGE
    WEB --> MON
    API --> MON
    WORKER --> MON

```

### 17.2 CI pipeline

Every pull request should run the applicable checks:

1. Dependency and lockfile validation.
2. Ruby formatting and linting.
3. TypeScript and Svelte checks.
4. Backend unit and integration tests.
5. Frontend tests.
6. API contract validation.
7. Architecture boundary checks.
8. Security and dependency scans.
9. Production builds.
10. Selected end-to-end tests.

Block merging when mandatory checks fail.

### 17.3 Environments

Maintain separate development, testing, staging, and production environments.

Use environment-specific credentials and configuration. Production data must not be copied into lower environments without approved sanitization.

### 17.4 Database and background jobs

- Run migrations through a controlled deployment step.
- Use expand-and-contract migrations for incompatible schema changes.
- Make background jobs idempotent where retries can duplicate effects.
- Use bounded retries with backoff.
- Route permanently failing jobs to an inspectable failure workflow.
- Alert on sustained queue delays.
- Never assume a job runs exactly once.

### 17.5 Observability

Track:

- API latency and errors.
- Database connection and query performance.
- Background queue depth and processing latency.
- WebSocket connection health.
- Session event delivery latency.
- Submission failures and duplicate conflicts.
- Frontend exceptions.
- Storage and backup health.
- Resource utilization.
- Integration and webhook failure rates.

Use structured logs and correlation IDs. Keep sensitive learner data, credentials, and private answer content out of logs unless there is a clearly justified, tightly controlled need.

### 17.6 Backups and recovery

Before production launch, define and test:

- PostgreSQL backups and restoration.
- Point-in-time recovery where supported.
- Object-storage recovery.
- Encryption and access controls.
- Recovery time objective (RTO).
- Recovery point objective (RPO).
- Procedures for restoring service after data corruption or infrastructure failure.

A successful backup job is not proof that the system can be recovered. Restoration must be tested.

## 18. Phased implementation plan

The implementation must proceed in dependency order, with a working product emerging incrementally. The estimates below are planning ranges, not delivery guarantees.

## P0

Foundation

Architecture and engineering foundation

1–2 weeks

- Establish the repository and domain boundaries.
- Configure Rails, SvelteKit, PostgreSQL, and local containers.
- Define coding standards and architectural rules.
- Establish CI, testing, OpenAPI, and validation conventions.
- Build initial design tokens and record critical ADRs.

## P1

Core

Identity, content, and assessment

3–5 weeks

- Implement authentication, authorization, and organizations.
- Implement activity and question versioning.
- Build the question registry and grading contracts.
- Deliver single-choice, multiple-select, true/false, and short-answer questions.
- Build the learner player and educator editor.
- Implement attempts, submissions, and scoring.

## P2

Sessions

Teacher-paced and student-paced learning

3–5 weeks

- Add assignments, deadlines, and attempt policies.
- Implement live sessions and joining codes.
- Add Action Cable events and reconnection handling.
- Protect against duplicate submissions and invalid state transitions.
- Build educator controls and learner progress views.

## P3

Experience

Gamification, animations, and reports

2–4 weeks

- Add teams, achievements, and leaderboards.
- Implement the shared animation and feedback system.
- Add reports and asynchronous exports.
- Improve mobile usability and accessibility.
- Add additional question types according to demand.

## P4

Release

Production readiness

2–4 weeks

- Complete security and privacy reviews.
- Test architectural boundaries and API compatibility.
- Perform load and resilience testing.
- Verify backup restoration.
- Configure monitoring, alerts, and deployment procedures.
- Run an educator and learner pilot.

## P5

Expansion

Advanced capabilities and integrations

- Add LMS integrations and partner APIs.
- Add AI-assisted content creation.
- Implement advanced assessment and mastery journeys.
- Expand enterprise administration and reporting.
- Evaluate separate Go services if measured needs justify them.

The phases can overlap where dependencies allow. For a small team, a realistic schedule may be longer than these ranges, particularly when implementing secure real-time sessions, robust assessments, and enterprise-grade operational controls.

## 19. Non-functional requirements and release gates

| Area                 | Initial target                                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------------------- |
| API performance      | p95 below 300 ms for ordinary requests under an agreed test load, excluding long-running operations. |
| Real-time delivery   | p95 below 500 ms under the defined test conditions.                                                  |
| Availability         | Initial production target of 99.9% monthly, subject to infrastructure and operational readiness.     |
| Accessibility        | WCAG 2.2 AA baseline.                                                                                |
| Frontend performance | Target LCP ≤ 2.5 seconds, INP ≤ 200 ms, CLS ≤ 0.1 at the 75th percentile.                            |
| Security             | No unresolved critical or high-severity release-blocking vulnerabilities.                            |
| Data integrity       | No silently lost acknowledged submissions under the documented durability and recovery model.        |
| Scalability          | Demonstrated performance against agreed concurrent-session and submission workloads.                 |
| Maintainability      | Enforced module boundaries, documented contracts, automated tests, and reviewed migrations.          |
| Recovery             | Explicit, tested RPO and RTO before production launch.                                               |

These are proposed targets. They must be validated in representative environments before being treated as achieved service levels.

A feature or release must not be approved simply because the interface works. It must also meet its acceptance criteria, security requirements, validation rules, testing obligations, and operational readiness requirements.

## 20. Architecture Decision Records

Create an ADR for each significant architectural decision. The initial set should include:

| ADR | Decision                                          |
| --- | ------------------------------------------------- |
| 001 | Modular Rails monolith and SvelteKit frontend     |
| 002 | Active Record and PostgreSQL                      |
| 003 | REST API versioning and OpenAPI contract          |
| 004 | Authentication, sessions, and authorization       |
| 005 | Organization tenancy and isolation                |
| 006 | Question registry and versioned schemas           |
| 007 | Immutable content and historical grading          |
| 008 | REST commands and Action Cable events             |
| 009 | Idempotency and concurrency control               |
| 010 | Validation and error-handling conventions         |
| 011 | Domain dependency rules and architectural testing |
| 012 | Integration adapters and webhook reliability      |
| 013 | Design system, animations, and accessibility      |
| 014 | CI/CD, observability, backups, and recovery       |
| 015 | Criteria for extracting specialized services      |

Each ADR should record the context, decision, alternatives considered, consequences, and conditions that could justify revisiting the decision.

## 21. What makes this architecture genuinely modular?

The structure alone will not guarantee quality. The following practices must remain mandatory throughout development.

- One authoritative implementation per business rule. No duplicated grading, permission, or session-transition logic.
- One clear owner per domain. Other modules use public interfaces instead of accessing private implementation details.
- Small, cohesive files. Split files when their responsibilities diverge; avoid both enormous files and meaningless fragmentation.
- Validation at every trust boundary. Validate schemas, permissions, business rules, and persistence invariants at the appropriate layers.
- RESTful, documented contracts. Frontend and external integrations depend on stable API definitions.
- Automated architecture enforcement. Detect forbidden dependencies and API contract violations in CI.
- Testable domain logic. Business rules should be testable without rendering the frontend or making real calls to external providers.
- Disciplined SDLC. Requirements, design, implementation, review, testing, release, and maintenance are part of every feature.
- Measured scaling. Improve database queries and job processing before introducing distributed infrastructure unnecessarily.
- Integration by contract. External providers can be replaced without rewriting the learning domain.

## 22. Recommended first implementation milestone

The best starting point is not to create every directory and every planned module at once. It is to establish the architecture and prove that it works with one complete, end-to-end user journey.

## Milestone 1: A complete learning journey

1. Set up the Rails API, SvelteKit application, PostgreSQL database, and CI pipeline.
2. Implement authentication, organization scoping, and authorization policies.
3. Create the activity and question-versioning model.
4. Implement a validated single-choice question type through the question registry.
5. Build the educator editor and learner player.
6. Implement assignment creation, attempts, answer submission, and authoritative scoring.
7. Document the REST API using OpenAPI and validate the frontend contract against it.
8. Add unit, integration, request, security, and end-to-end tests.
9. Verify that the module boundaries and DRY principles are enforced by automated checks.

Once this milestone is working, the team can add question types, student-paced assignments, live sessions, gamification, and richer animations without changing the fundamental architecture.

Final recommendation: KINGDOM Quest should be built as a modular Rails application with SvelteKit and PostgreSQL, using Active Record, a contract-driven REST API, explicit domain boundaries, validation-first development, and an enforced SDLC. This gives EKD Digital a maintainable foundation that can grow into an advanced educational platform without prematurely introducing the complexity of microservices.