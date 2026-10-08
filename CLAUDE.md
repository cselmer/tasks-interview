# CLAUDE.md

How we write code at Tern, scoped to this app.

This is a small Rails app used as the starting point for a pair-programming
interview. Keep changes simple, idiomatic, and easy to read. Prefer plain Rails
over abstractions — reach for a new pattern only when the code genuinely calls
for it, not preemptively.

## Stack

- Ruby 4.0.5, Rails 8.1, PostgreSQL 18
- Hotwire (Turbo + Stimulus) with import maps; Propshaft for assets
- Tailwind CSS via `tailwindcss-rails`
- RSpec + FactoryBot + Faker for tests
- Authentication is session-based and hand-rolled (`has_secure_password`,
  `current_user`) — no Devise. Leave it that way unless asked.

## Setup

- Run `bin/setup --skip-server` first in every checkout, including each git
  worktree. Databases and the `bin/dev` port derive from the checkout's path,
  so checkouts never share data. Ruby comes from `.ruby-version`; don't add
  other version-manager files (`.tool-versions`).
- `bin/ci` is the gate before a PR: setup, the importmap audit, `standardrb`,
  the RSpec suite, then `db:seed:replant` against the test database — so seeds
  must load under every validation on the branch.
- Seeds are keyed by title and idempotent (`find_or_initialize_by` + `update!`).
  `bin/rails db:seed` refreshes their relative dates; `db:seed:replant` resets
  them.
- After writing a migration, `git diff db/schema.rb` must contain only the
  version bump and this branch's own change.
- Tailwind is built by `bin/setup` and watched by `bin/dev`. After adding
  utility classes with no watcher running, `bin/rails tailwindcss:build`; the
  suite only rebuilds when the bundle is missing.

## Code style

We follow [standardrb](https://github.com/standardrb/standard). Match its
defaults rather than inventing a house style:

- Double-quoted strings, 2-space indentation, no frozen-string pragma needed.
- Use Ruby idioms: `?` suffix for predicates, `!` for mutating/bang methods.
- `do`/`end` for multi-line blocks, `{ }` for one-liners.
- Multi-line hashes and arrays: one element per line.

Naming and structure:

- Names should reveal intent — descriptive but not verbose. Spell out variables
  (`task`, not `t`).
- Prefer keyword arguments over positional ones, and use the `foo:` shorthand
  when the local matches the parameter. Avoid `**options` splats — they hide the
  real API.
- Memoize with an `@_`-prefixed ivar: `@_user ||= User.find(...)`.
- Namespace classes with a flat declaration (`class Tasks::Export`), not nested
  `module` blocks.

Comments:

- Default to none — let the code read clearly on its own.
- When you do comment, explain the *why* (a non-obvious workaround, a business
  rule, a security reason), never the *what*.

Don't add code that isn't used yet — no methods, scopes, or helpers without a
caller in the same change.

## Rails conventions

- **Controllers** stay RESTful and thin. Use `before_action` for auth and
  shared setup. Permit params explicitly with
  `params.require(:task).permit(...)`. Handle both the success and failure
  branches of a save — don't leave the failure path empty, and render it with
  `status: :unprocessable_content`. A failed `create` re-renders `index`, so
  it must load everything `index` loads.
- **Models** hold validations, associations, and scopes. Keep callbacks to a
  minimum; prefer explicit calls from the controller or a service.
- **Views** are ERB. Pull repeated markup into partials
  (`tasks/_form.html.erb`) and style with Tailwind utility classes inline. Put
  view logic in helpers, not in the template.
- Eager-load (`includes`) every association a rendered collection touches. The
  index renders more than one collection; each one needs it.
- Dates go through the app zone: `Date.current`, `Date.tomorrow`, `Time.zone`,
  never `Date.today` or `Time.now`. `config.time_zone` is UTC, so "today"
  rolls over at UTC midnight.
- `tasks.complete` is nullable with no default and the new-task form never
  sets it, so a task created through the form stores `NULL`. Treat `NULL` as
  incomplete (`Task.incomplete`), never `where(complete: false)`.
- When business logic outgrows a controller action or model, extract a plain
  service object (`SomeService.call(user:, params:)`) rather than fattening the
  controller. Keep it to what the task needs — don't build a framework.

## Testing

- Write specs for behavior you add or change; cover both the happy path and the
  failure path.
- Use FactoryBot (`build`/`create`) with Faker for data; keep factories minimal
  and valid by default.
- Test through the public interface — never reach into private methods, and
  don't test framework configuration.
- Prefer real objects over mocks in the happy path; reserve stubs for external
  services and hard-to-reach edge cases.
- In request specs, assert `have_http_status` before reading `response.body`,
  `assert_select`, or `response.parsed_body` — every time, and again after
  `follow_redirect!` — so a 500 reads as a 500 rather than as missing content.
- Request specs see rendered error pages, not raised exceptions (Rails 8.1
  reads the test environment's `show_exceptions = false` as "show"). Assert the
  status there, and pin a raise in a model spec.
- Request specs pin what the view emits, not just what the controller accepts:
  the form's fields, a `button_to`'s `_method`, the row a value appears in.
  Use `assert_select` or `response.parsed_body` (Nokogiri) to scope assertions;
  Capybara matchers are not available in request specs. If a spec stays green
  after you delete the form field or the `includes` it covers, it covers nothing.
- Shared helpers live in `spec/support` (autoloaded by `rails_helper`) and take
  keyword arguments. `sign_in(user:)` posts a real login, so use a factory user;
  seeded users have no in-memory password. `travel_to` comes from
  `spec/support/time_helpers.rb` and freezes `created_at` too.
- Mailer previews live in `spec/mailers/previews`.
- Run `bin/ci` before opening a PR; `bundle exec rspec` alone skips `standardrb`
  and the seeds.

## Companion changes

A change to one of these paths is not complete until its companion changes
too, or the reason it does not is written down (in the PR description, or
under "Not done" in the claims block when the change came from `/work`):

- Anything under `.claude/` (skills, agents, hooks, `settings.json`) changes
  the Claude Code section of `README.md`.
- `bin/setup`, `bin/ci`, `config/ci.rb`, `config/database.yml`, `bin/dev`, or
  `Procfile.dev` changes the Setup and Local Development sections of
  `README.md` and the Setup section of this file.
- A migration changes `db/schema.rb`; a new column the UI shows changes
  `db/seeds.rb` and the form or index specs.
- A mailer gets a preview under `spec/mailers/previews`.
- A new route gets a request spec that exercises it.

## Git & PRs

- Never commit directly on `main` or your personal base branch; they only
  receive merges of reviewed branches. Branch from the base, then open a PR
  against it.
- When you have a personal base branch, record it once with
  `git config review.base <branch>`, and name the base when you run `/review`
  (it assumes `main`).
- Keep PRs small and focused on one logical change; nothing outside the
  change's area — no `Gemfile`, `config/environments`, or schema edits the
  change did not call for.
- Write a description that says what changed and how to verify it (the manual
  steps a reviewer should take). Self-review the diff before requesting review.
