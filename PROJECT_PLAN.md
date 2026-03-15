# MojoTodo - Project Plan

## Project Overview

A lightweight single-page web application (SPA) for collaborative todo list management built with
Mojolicious and SQLite3.

### Key Features
- Multi-user support with authentication
- Multiple todo lists per user
- Task sharing between users
- Deadline tracking with visual indicators for late/nearly late tasks
- RESTful API for potential iOS client integration

### Design Principles
- Lightweight and minimal dependencies
- Convention over Configuration
- Use only core Perl modules where possible
- Simple, testable architecture

---

## PENDING TASKS

### MVP Execution Order and Release Gates

Execution order for fastest safe delivery:
1. Phase 0 -> resolve design decisions before schema/API work.
2. Phase 1 -> wire DB config/startup/schema behavior.
3. Phase 2 -> lock model contract conventions.
4. Phase 3 -> implement core models and relationships.
5. Phase 4 -> migration/seed/reset operational tooling.
6. Phase 5 -> implement API endpoints and authorization.
7. Implementation Hardening -> harden OTP/auth core before expanding API surface.
8. Phase 7 -> complete test coverage for implemented features.
9. Phase 9 -> apply broader security hardening required for exposure.
10. Phase 10 -> apply performance and operational protections.
11. Phase 6 -> build SPA views after API contract stabilizes.
12. Phase 8 -> finalize docs/deploy runbook.

Release gate tags:
- [MUST-HAVE BEFORE API ALPHA] Phase 0, Phase 1, Phase 2, Phase 3, Phase 4,
  Phase 5 (excluding sharing extras), Implementation Hardening, and Phase 7
  tests for those phases.
- [MUST-HAVE BEFORE EXTERNAL/API BETA] Complete remaining Phase 9 items
  (session fixation mitigation, CSRF strategy, request size limits,
  injection/XSS test coverage, cleanup jobs) and run full security test suite.
- [MUST-HAVE BEFORE PRODUCTION] Complete remaining Phase 9 and Phase 10,
  and complete Phase 8 documentation/deployment checklist.
- [CAN DEFER POST-MVP] `TaskComment` model, advanced sharing model expansion,
  and non-critical UI polish not required for functional workflows.

### Phase 0: Design Consistency and Decisions
- [x] Resolve sharing scope inconsistency: implement both list sharing and task assignment for MVP.
- [x] Align API with sharing choice: list-level sharing + explicit task assignment endpoints.
- [x] Pick canonical share model: `ListShare` (remove `TaskShare` as sharing model).
- [x] Define shared-list permission mode as edit-only for collaborators.
- [x] Define assignment behavior as linked/shared task instance across lists (not copy or move).
- [x] Define source-list UX behavior for assigned tasks: show assignee email and provide easy hide filter.
- [x] Define completion behavior for assigned tasks: any user with edit access to target list can complete.
- [x] Define revocation behavior for assigned tasks: keep assigned tasks after list share revocation.
- [x] Define notification scope for MVP: in-app notifications only.
- [x] Define canonical naming standard:
      tables use plural snake_case, model classes use singular UpperCamelCase,
      relationship methods use snake_case, foreign keys use `<singular>_id`,
      JSON payload keys use snake_case, and routes use `/api/lists` + `/api/tasks` domain terms.
- [x] Use explicit `foreign_key` in all relations (do not rely on Durance defaults for compound names).
- [x] Define canonical login identifier strategy: email-only for MVP; phone/SMS deferred.
- [x] Define passwordless auth UX contract: request code, verify code, session established.
- [x] Set one-time code policy:
      8-digit codes, 10-minute TTL, 30-second resend cooldown,
      max 5 verify attempts per active code,
      invalidate all active codes on successful verify,
      and on max attempts expire code and require a new request.
- [x] Implement agreed policy: unrecognized email is auto-created only after successful code verification.
- [x] Define authorization matrix for owner, collaborator, and non-member actions per endpoint:
      `GET /api/lists/:id` = owner + collaborator;
      `PATCH/DELETE /api/lists/:id` = owner only;
      `POST /api/lists/:id/tasks` = owner + collaborator;
      task edit/complete/delete in accessible list = owner + collaborator;
      `POST/DELETE /api/lists/:id/share` = owner only;
      `POST /api/tasks/:id/assign` = user with edit on source and access to target list;
      assignment removal = source owner OR target owner OR assigner;
      notifications = self-only read/update;
      non-member access = 404;
      revoked collaborators lose access on next request.

### Phase 1: Dependency and ORM Integration (Durance)
- [x] Add `Durance` to `cpanfile` as a non-CPAN dependency (pin to source until CPAN release).
- [x] Document local development setup to load `/home/jjohn/src/durance/lib` via `PERL5LIB`.
  - Local shell setup command:
    `export PERL5LIB="/home/jjohn/src/durance/lib:${PERL5LIB}"`
  - One-off test command example:
    `PERL5LIB="/home/jjohn/src/durance/lib:${PERL5LIB}" prove -l t/`
  - Test DB override option:
    `MOJOTODO_DBNAME=t/test.db` (used by tests to keep SQLite under `t/`).
  - This is local-dev only; deployment should resolve `Durance` through `cpanfile` dependency
    installation.
- [x] Create `lib/mojotodo/DB.pm` extending `Durance::DB`.
- [x] Add Mojolicious config file `mojotodo.conf` read at startup via `plugin('Config')`.
- [x] Add `database => { dsn => ... }` configuration structure in `mojotodo.conf`.
- [x] Set default DSN to `dbi:SQLite:dbname=app.db` (create `app.db` at workspace root).
- [x] Implement `_build_dsn` in `lib/mojotodo/DB.pm` to use config DSN first.
- [x] Add environment variable override (for deploy) that supersedes config DSN.
- [x] Add a startup hook that initializes `Durance::Schema`.
- [x] Validate configured DSN at startup and fail fast with a clear error if invalid.
- [x] In development mode, call `sync_table(...)` for core auth models on startup.
- [x] In production mode, call `ensure_schema_valid(...)` for each model class.

### Phase 2: Model Contract (what Durance requires)
- [x] Define model namespace `lib/mojotodo/Model/*.pm`.
- [x] Ensure each model `use Moo; extends 'Durance::Model'; use Durance::DSL;`.
- [x] Define `tablename '...'` explicitly in each model.
- [x] Define columns with `column <name> => (...)` including `id` with `primary_key => 1`.
- [x] Use supported Durance types (`Int`, `Str`, `Text`, `Bool`, `Float`, `Timestamp`).
- [x] Add `created_at` and `updated_at` columns where auto timestamps are desired.
- [x] Add `validates` rules for format/length where input quality matters.
- [x] Define relationship metadata with Durance DSL (`has_many`, `belongs_to`, `has_one`,
      `many_to_many`) and explicit `foreign_key` where non-default.

### Phase 3: Core Data Model Implementation
- [x] Create `mojotodo::Model::User` with email identity and account status columns.
- [x] Add unique constraint and format validation for `email`.
- [x] Create `mojotodo::Model::AuthChallenge` (or `LoginCode`) for one-time login codes.
- [x] Add challenge fields: `user_id` (or `email`), `code_hash`, `expires_at`, `used_at`,
      `attempt_count`, `created_at`.
- [ ] FUTURE IMPLEMENTATION (waiting-on-vendor): add indexes for challenge lookup and expiration
      cleanup (`email/user_id`, `expires_at`) once Durance index-definition support is available.
- [x] Create `mojotodo::Model::TodoList` with owner foreign key and list metadata.
- [x] Add `belongs_to user` on `TodoList` and `has_many todo_lists` on `User`.
- [x] Create `mojotodo::Model::Task` with list foreign key, status, due date, and timestamps.
- [x] Add `belongs_to todo_list` on `Task` and `has_many tasks` on `TodoList`.
- [x] Create `mojotodo::Model::ListShare` as the join model between user and todo list.
- [x] Create `mojotodo::Model::TaskAssignment` (or `TaskListLink`) to link one task across lists.
- [x] Add assignment metadata fields (`assigned_by_user_id`, `assigned_to_user_id`, `source_list_id`).
- [x] Add query support for source-list visibility filter (`hide_assigned_out`) and assignee labeling.
- [x] Define exact `TodoList` schema fields:
      `id`, `owner_user_id`, `title`, `archived`, `created_at`, `updated_at`.
- [x] Define exact `Task` schema fields:
      `id`, `todo_list_id`, `title`, `description`, `status`, `due_at`, `completed_at`,
      `created_by_user_id`, `created_at`, `updated_at`.
- [x] Define exact `ListShare` schema fields:
      `id`, `todo_list_id`, `user_id`, `created_by_user_id`, `created_at`, `updated_at`.
- [ ] Add `ListShare` uniqueness and indexes:
      unique (`todo_list_id`, `user_id`), indexes on `user_id` and `todo_list_id`.
- [x] Define exact `TaskAssignment` schema fields:
      `id`, `task_id`, `source_list_id`, `target_list_id`, `assigned_by_user_id`,
      `assigned_to_user_id`, `created_at`, `updated_at`.
- [ ] Add `TaskAssignment` uniqueness and indexes:
      unique (`task_id`, `target_list_id`), indexes on `source_list_id`, `target_list_id`,
      `assigned_to_user_id`, and `task_id`.
- [ ] Define exact in-app `Notification` schema fields:
      `id`, `user_id`, `type`, `title`, `body`, `reference_type`, `reference_id`, `read_epoch`,
      `created_at`, `updated_at`.
- [ ] Add `Notification` indexes for inbox queries:
      (`user_id`, `read_epoch`, `created_at DESC`).
- [ ] Add optional `TaskComment` model only if collaboration notes are needed for MVP.

### Phase 4: Schema and Data Lifecycle
- [ ] Add `script/migrate` command to run `migrate_all('mojotodo::DB')` manually.
- [ ] Add seed script for local data (`script/seed`) using model `create(...)` APIs.
- [ ] Add a documented reset flow for dev DB recreation.

### Phase 5: API Endpoints (Mojolicious)
 - [x] Add `/api/auth/request-code` endpoint to request one-time login code by email.
 - [x] Add `/api/auth/verify-code` endpoint to verify code and establish authenticated session.
 - [x] Add `/api/logout` endpoint to end authenticated session.
 - [ ] Add optional `/api/auth/resend-code` endpoint with cooldown controls.
 - [x] Add `/api/lists` CRUD endpoints.
 - [ ] Add `/api/lists/:id/tasks` endpoints for task CRUD within a list.
 - [ ] Add `/api/lists/:id/share` endpoint(s) for list collaboration controls.
 - [ ] Add `/api/tasks/:id/assign` endpoint(s) to link tasks into another user's list.
 - [x] Add `/api/lists/:id/tasks?hide_assigned_out=1` filter behavior for source-list UX.
 - [ ] Define `/api/lists/:id/share` contract:
       POST `{ email }`, DELETE by share id or email, GET collaborators.
 - [ ] Define `/api/tasks/:id/assign` contract:
       POST `{ target_list_id, assigned_to_email }`, DELETE assignment id, GET assignments.
 - [ ] Define source-list projection contract for assigned tasks:
       include `assigned_to_email`, `is_assigned_out`, and `target_list_id` when present.
 - [ ] Add in-app notification endpoints:
       `GET /api/notifications`, `POST /api/notifications/:id/read`,
       `POST /api/notifications/read-all`.
 - [ ] Add authorization checks so users only access owned/shared resources.
 - [ ] Add API error format conventions for validation and auth failures.

### Immediate Remediation Tasks (Pre-MVP Exposure)

#### Testability Gaps
- [ ] Add API integration tests for list CRUD endpoints (create, read, update, delete).
- [ ] Add API integration tests for task list endpoint with hide_assigned_out.
- [ ] Add auth + list + task flow integration tests.
- [ ] Add test isolation: each test should use a fresh in-memory or temp database.

#### Security Gaps
- [x] Fix collaborator access: list GET endpoints should return lists owned OR shared with current user.
- [x] Add collaborator-aware authorization to task list endpoint.
- [ ] Add input sanitization for title/description fields to prevent XSS when rendered.
- [ ] Add request size limits for JSON payloads at application level.
- [ ] Add basic rate limiting middleware for state-changing endpoints (lists/tasks).

#### Scalability Gaps
- [ ] Add pagination to list endpoints (default 20, max 100).
- [ ] Add default sorting (id DESC) to list endpoints for consistent paging.
- [ ] Optimize list_view N+1: batch-load assignments in single query rather than per-task loop.

### Implementation Hardening

Findings recorded from implementation review:
- Current auth flow has security exposure risks (OTP leakage via logs/dev response defaults,
  weak fallback secrets/pepper, and incomplete abuse controls).
- Current auth verification path has architectural/consistency risks (non-atomic single-use
  verification and route-closure-heavy auth logic in `startup`).
- Current implementation has design gaps (missing cleanup/index hardening and incomplete
  error/session hardening for externally exposed API usage).

Next pass hardening steps:
- [ ] OTP core hardening (issuance + verification) as one combined pass:
  - [ ] Stop OTP leakage in logs and responses:
    - [ ] Remove code value from application logs in all modes.
    - [ ] Restrict `dev_return_code` so it is only enabled in explicit local development/testing
          configuration.
    - [ ] Add startup guard that fails in non-development if `dev_return_code` is enabled.
  - [ ] Enforce strong secret/pepper configuration:
    - [ ] Remove weak fallback secret/pepper defaults used by runtime code.
    - [ ] Require explicit secret/pepper in non-development startup and fail fast if missing.
    - [ ] Add config validation tests for secret/pepper requirements by environment.
  - [ ] Make OTP verify single-use and race-safe:
    - [ ] Add transactional verification flow (`begin_work`/`commit`/`rollback`) around challenge
          read+update and user creation.
    - [ ] Verify only the newest eligible challenge record for the email.
    - [ ] Update challenge consumption atomically (`used_epoch`, `attempt_count`) before returning
          authenticated response.
    - [ ] Add replay/race tests that run concurrent verify attempts and assert only one success.
    - [ ] Add failure-path tests to ensure transaction rollback preserves consistency.
- [ ] Add structured auth abuse protections and error hardening (rate limits for request/verify,
      sanitized failures, bounded request payload handling).
  - [ ] Implement baseline rate limits:
        request-code = 5 per 15 minutes (per email+IP),
        verify-code = 20 per 15 minutes (per email+IP).
- [ ] Refactor auth flow from route closures into controller/service modules for maintainability,
      clearer testing seams, and safer future extension.

### Phase 6: SPA UI (Bootstrap)
- [ ] Build base SPA shell and passwordless auth views (email entry + code verification).
- [ ] Build list management UI (create/rename/archive lists).
- [ ] Build task management UI (create/edit/complete/reorder tasks).
- [ ] Add due-date visual states (on-time, nearly late, late).
- [ ] Add sharing UI to grant/revoke access to users.
- [ ] Ensure responsive layouts for phone-sized and desktop screens.

### Phase 7: Testing (feature-first and regression-safe)
- [ ] Add unit tests for each model: CRUD, validations, and relationships.
- [ ] Add schema tests for `migrate_all`, `sync_table`, and `ensure_schema_valid` behavior.
- [ ] Add config tests for DSN resolution order: env override > Mojolicious config > default `app.db`.
- [ ] Add startup tests for DSN validation failure and schema validation failure paths.
- [ ] Add controller/API tests for auth code request, verify, resend, logout, lists, tasks, and sharing.
- [ ] Add tests for code expiration, single-use enforcement, max attempts, and resend cooldown.
- [ ] Add authorization tests for cross-user data isolation.
- [ ] Add tests that unknown JSON fields are ignored/rejected (prevent mass-assignment style bugs).
- [ ] Add edge-case tests for due-date boundaries and overdue transitions.
- [ ] Add pagination tests for list/task collection endpoints (`limit`, `offset`, stable ordering).
- [ ] Add concurrency tests for simultaneous task updates and share/unshare race conditions.
- [ ] Run full suite with `prove -l t/` and keep green after each feature slice.

### Phase 8: Documentation and Deploy Readiness
- [ ] Update README with local dev setup (including local Durance usage).
- [ ] Document deployment dependency strategy for Durance in `cpanfile`.
- [ ] Document schema migration strategy for dev vs production.
- [ ] Document API routes and expected request/response payloads.
- [ ] Add an initial deployment checklist (env vars, DB path, startup command).

### Phase 9: Security Hardening
- [x] Store one-time codes as hashes only (never plaintext) and compare using constant-time logic.
- [ ] Regenerate session identifier at login to reduce session fixation risk.
- [ ] Decide and enforce CSRF protection strategy for cookie-authenticated state-changing routes.
- [ ] Add request size limits for JSON payloads to reduce abuse and accidental memory pressure.
- [ ] Add security tests for SQL injection payloads in query parameters and JSON bodies.
- [ ] Add security tests for stored and reflected XSS in task/list names rendered by the SPA.
- [ ] Add background cleanup task for expired/used auth challenges to reduce attack surface.

### Phase 10: Performance and Operational Safety
- [ ] Add indexes for hot query paths (`user_id`, `todo_list_id`, `due_at`, share lookup columns).
- [ ] Add tests or checks that verify required indexes exist after schema migration.
- [ ] Avoid N+1 query patterns by using `preload`/`include` for list+task and share lookups.
- [ ] Add API-level pagination defaults and max page size limits.
- [ ] Add sorting conventions for deterministic paging (for example, `created_at DESC, id DESC`).
- [ ] Add query-count assertions for critical endpoints to catch regression in relationship loading.
- [ ] Add SQLite operational settings guidance (WAL mode, busy timeout) for multi-user write load.
- [ ] Add startup timing check to ensure schema checks do not cause unacceptable boot latency.

---

## Completed Tasks

Progress is tracked inline via checked tasks `[x]` in each phase.
