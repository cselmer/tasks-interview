---
name: work
description: Build a change from written requirements. Orients in the repo, plans, implements with specs on a feature branch off the base, gates with standardrb and bin/ci, mutation-checks each claim, and commits with a claims block that /qa reads. Use when asked to implement a ticket, an email excerpt, or a one-line requirement.
argument-hint: "<requirements: a ticket, an email excerpt, or a sentence> [--base <branch>]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, AskUserQuestion
model: inherit
---

# /work

Turn requirements into one branch that is ready for `/qa` and `/review`. This
is a small ERB-based Rails app — keep the change proportional to the request
and grounded in `CLAUDE.md` (the team's conventions). You are the builder: get
help exploring if you need it, but write the code and specs yourself, and end
with a claims block that `/qa` checks line by line against the diff.

**When not to use this:** not for planning only (use `/plan`), not for
reviewing a branch (use `/qa` or `/review`), and never for work committed on
`main` or the base.

## Input

<task_input>$ARGUMENTS</task_input>

## Guidance: briefing subagents

When you launch an `Explore` agent (via the `Agent` tool), it starts fresh with
zero context — it hasn't seen this conversation. Brief it like a colleague who
just walked in: what you're trying to accomplish and why, what you've already
learned or ruled out, and the specific files/areas to look at. Terse prompts
produce shallow work. Never offload synthesis onto an agent ("based on your
findings, implement it") — do the understanding yourself and tell the agent
exactly what you need. Give every agent an explicit `model`, never an inherited
one: `sonnet` by default, `opus` only for a design question that spans several
areas. Never delegate the implementation itself.

## Vocabulary

- **Base**: the branch the work diffs against and will merge into (Step 2).
- **Gate**: `bin/ci` (what it runs: `CLAUDE.md`, **Setup**). Green means exit
  0. Nothing is done until the gate is green.
- **Area**: the set of paths a requirement legitimately touches. Anything
  outside it is a side effect unless the requirement called for it.
- **Claims block**: the summary this run ends with and `/qa` reads (Step 8).

## Local toolchain

Ruby comes from `.ruby-version`. If `ruby -v` does not print that version, the
developer's version manager needs an exec wrapper in front of every `ruby`,
`bundle`, and `bin/*` command. Use it for every command, and never write it, or
any absolute local path, into a committed file (code, spec, commit message,
claims block). Never add `.tool-versions` or touch `.ruby-version` /
`.ruby-gemset`.

## Step 1: Interpret the input

Read the requirements in `<task_input>`; set aside a `--base <branch>` if any.

- **Empty** → when a person is present, ask for the requirements; otherwise
  stop and say that none were given.
- **Ambiguous** (an edge, a default, wording that reads two ways) → when a
  person is present, ask with `AskUserQuestion`. When running non-interactively
  (as a subagent, under `claude -p`, or whenever no answer can arrive), choose
  the simplest reading, record it for "Assumptions", and continue.
- If another branch is being built in parallel off the same base, keep edits
  to the files it also touches to the smallest line-level change.

## Step 2: Resolve the base and create the branch

Resolve the base in this order, each step falling through quietly:

1. `--base <branch>` from the arguments.
2. `gh pr view <branch> --json baseRefName -q .baseRefName` (empty with no
   PR, no `gh`, or no network — always so for a branch not yet created).
3. `git config review.base` (see `CLAUDE.md`, **Git & PRs**).
4. `main`.

Say which base you resolved and which step gave it. Then:

- `git status --short` must be empty; if not, stop and say what is in the way
  (never `git stash` it).
- Name the branch `<prefix>/<slug>`: `<prefix>` is the base's own `name/`
  prefix (base `jdoe/base` → `jdoe/`), or the first word of
  `git config user.name` in lowercase when the base is `main` or has no such
  prefix; `<slug>` is a few kebab-case words naming the change.
- `git switch -c <prefix>/<slug> <base>`. Never commit on `main` or the base.

## Step 3: Orient

Run `bin/setup --skip-server` once in this checkout (idempotent). Read
`CLAUDE.md` in full — this skill leans on its **Setup**, **Rails conventions**,
**Testing**, and **Git & PRs** sections without repeating them — then the files
the work touches (Repo layout, below) and their specs. Explore and plan inline
by default; launch one `Explore` agent (`model: sonnet`), briefed as above,
only when the work spans more than about three files or an area not yet read.

## Step 4: Plan

Write the plan down in a few lines before editing: the area (every path you
expect to touch), each behavior you will claim and the spec that will prove
it, and the readings chosen in Step 1. Reuse what exists — `load_tasks`, the
`Task` scopes, the helpers, `spec/support` — before adding anything. If the
requirement cannot work without a change outside the area (a `Gemfile` or
`config/environments` edit, say), ask when a person is present; otherwise leave
it out and record it under "Not done" with the reason.

## Step 5: Implement, spec first

Where practical, write each behavior's example first, run
`bundle exec rspec <file>`, and see it fail for the right reason; then write
the code and see it pass. Follow `CLAUDE.md` and the Traps below. Name each
example for what it pins, and don't test Rails itself.

- Schema change: `bin/rails generate migration <Name> ...`, then
  `bin/rails db:migrate`, then `git diff db/schema.rb` (trap 9).
- New utility classes, no `bin/dev` running: `bin/rails tailwindcss:build`.

## Step 6: Mutate what the user needs

Before reporting done, break each claim the way a user would feel it, not the
line you wrote: mutating your own code tends to confirm what you already
tested. Pick from: delete the `method:` from a `button_to`; remove a form
field; drop an `includes`; swap `Date.current` for `Date.today` (specs freeze
at noon UTC, so only a zone-boundary example like the `Pacific/Auckland` ones
in `spec/models/task_spec.rb` catches it); remove a validation or constraint.

Stage your work first (`git add <paths>`): `git checkout -- <file>` restores
from the index, so unstaged work in that file would be lost. Then, per claim:
make the minimal edit, run the spec the claim names, confirm it fails, and
restore with `git checkout -- <file>`. After every restore `git diff` is empty
and `git status --short` lists only your work.

A claim whose mutation leaves the suite green is not verified: strengthen the
spec (usually by asserting what the view emits, trap 2) and mutate again, or
drop the claim. Delete any probe spec you wrote.

## Step 7: Gate

Run `bundle exec standardrb` and fix what it reports, then `bin/ci`. Both must
be green before you commit; if the gate goes red, fix the cause and run it
again. Note the example count from the RSpec step.

## Step 8: Commit with the claims block

One commit per logical change, staged by explicit path (nothing under `tmp/`,
`log/`, or `app/assets/builds/`). The final commit's message is a one-line
imperative subject, a blank line, the claims block, a blank line, and the
attribution trailer your harness specifies. Pass it with `git commit -F -` and
a quoted heredoc (`<<'EOF'`) so nothing in it expands.

The claims block is the body of that final commit and later the PR
description. Keep this shape exactly, with no `#` headings (git drops them as
comments whenever a commit message is edited) and no local toolchain prefix:

```
Claims (base: <base>)

Files changed:
- <path>: <what changed, one line>

Behavior claimed:
1. <one observable behavior>
   Verified by: <spec file and example name, or the command and its result>
2. ...

Assumptions:
- <each reading of an ambiguous requirement that was chosen, and why>

Not done:
- <what was deliberately left out, and why>

Commands run:
- bin/ci (exit 0, <n> examples, 0 failures)
- ...
```

- "Files changed" lists every path in `git diff --stat <base>...HEAD` and
  nothing else. Every behavior names the spec or command that proves it.
- "Commands run" lists `bin/ci`, `bundle exec standardrb`, and each mutation
  as `<mutation>: bundle exec rspec <file> (<n> failures, restored)`.

After committing, compare `git diff --stat <base>...HEAD` with "Files
changed", and search the committed text for your toolchain wrapper and your
home directory (`git diff <base>...HEAD | grep -n "$HOME"`, and the same over
`git log <base>..HEAD --format=%B`). Fix anything off and rewrite the message
with `git commit --amend -F -`. No push, no PR, no bare `git stash`.

## Step 9: Report

End your last message with, in order:

1. If you have them, at most three short lines: weak spots you saw and left
   alone, and context you lacked that `CLAUDE.md` or this skill should give.
2. The claims block exactly as committed.
3. One line: run `/qa <branch>` and then `/review <branch>`. When the base is
   not `main` and did not come from `git config review.base`, write
   `/qa <branch> --base <base>` and say to name the base for `/review` too.

## Repo layout

- `app/controllers/tasks_controller.rb` — `load_tasks` builds every collection
  the index renders, for both `index` and the `create` failure path.
- `app/models/task.rb` — validations and the scopes `incomplete`,
  `due_soon_for(user:)`, `due_tomorrow`.
- `app/views/tasks/{index.html.erb,_form.html.erb,_task.html.erb}` — the page
  (form, Due Soon, All tasks), the form, and one row with its `button_to`.
- `app/helpers/tasks_helper.rb`, `app/services/tasks/`, `app/mailers/`,
  `db/seeds.rb`.
- `spec/requests/tasks_spec.rb` — the `users_queries_during` N+1 guard
  (counts at 2 and 6 tasks) and `parsed_body` helpers like `row_for(task:)`.
- `spec/models/task_spec.rb` (scopes, zone boundaries), `spec/factories/`,
  `spec/support/{authentication_helpers,time_helpers}.rb`.

## Traps

1. Request specs: `have_http_status` before `response.body`, `assert_select`,
   or `parsed_body`, and again after `follow_redirect!`.
2. Specs that only post params never pin the view: assert the form's fields,
   a `button_to`'s `_method`, the row a value is in.
3. `assert_select` and `response.parsed_body` work in request specs; Capybara
   matchers do not.
4. Request specs see rendered error pages, not raised exceptions; pin a raise
   in a model spec.
5. `status: :unprocessable_content`, never `:unprocessable_entity`.
6. `includes` on every collection the index renders, including the failure
   path's re-render (`load_tasks`).
7. `Date.current` / `Date.tomorrow` / `Time.zone`, never `Date.today` /
   `Time.now`; the zone is UTC.
8. `tasks.complete` is nullable; the form stores `NULL`; `Task.incomplete`
   treats `NULL` as incomplete.
9. After a migration, `git diff db/schema.rb` is the version bump plus this
   branch's change only; factories stay valid without defaults for new
   nullable columns.
10. Seeds are idempotent and `bin/ci` replants them; a new validation must not
    break `db/seeds.rb`.
11. `sign_in(user:)` posts a real login, so use a factory user. `travel_to`
    freezes `created_at`, so ordering specs set timestamps explicitly.
12. Rebuild Tailwind after new utility classes when `bin/dev` is not running.
13. Clean up probe specs; leave `ActionMailer::Base.deliveries` cleared; track
    nothing under `tmp/`, `log/`, or `app/assets/builds/`.

## Definition of done

- Branch off the base, diff inside the area, nothing on `main` or the base.
- The gate is green: `bin/ci` exits 0.
- Every claim is verified by a named spec that failed under its mutation.
- The claims block matches `git diff --stat <base>...HEAD` exactly.
- `git status` is clean; no committed text holds a toolchain wrapper or an
  absolute local path.
