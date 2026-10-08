---
name: qa
description: Check that a finished branch or PR does what its claims block says, without collateral damage. Compares the claims with the diff in both directions, runs the gate, exercises each claim, runs a mutation pass against what the user depends on, runs concrete side-effect checks, restores every mutation, and reports a PASS/FAIL verdict. Use after /work and before /review.
argument-hint: "[PR number, GitHub URL, or branch name — omit for the current branch] [--base <branch>]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent
model: inherit
---

# /qa

Check a finished branch against what its author says it does, and against what it
should not have touched. This is a small, ERB-based Rails app — keep the pass
proportional to the change. Read `CLAUDE.md` in full first and cite its sections
in findings rather than restating them. Every finding names the command behind it.

**When not to use this:** `/qa` is not a code review (`/review`), not a planner
(`/plan`), and not for a branch with uncommitted work — it mutates files and
restores them with `git checkout`, which would discard yours.

## Input

<task_input>$ARGUMENTS</task_input>

## Vocabulary

- **Base**: the branch the work diffs against and will merge into.
- **Gate**: `bin/ci` — `bin/setup --skip-server`, the importmap audit,
  `bundle exec standardrb`, `bundle exec rspec`, then `db:seed:replant` and
  `db:truncate_all` in the test database. Green means exit 0.
- **Area**: the set of paths a requirement legitimately touches. Anything outside
  it is a side effect unless the requirement called for it.
- **Claims block**: the plain-text summary `/work` ends with — the body of its final
  commit, the PR description, and this skill's input. It opens with
  `Claims (base: <base>)`, then labelled sections (no `#` headings):
  `Files changed:` (one `- <path>: <what changed>` per file), `Behavior claimed:`
  (numbered, each followed by a `Verified by:` line naming a spec file and example,
  or a command and its result), `Assumptions:`, `Not done:`, and `Commands run:`
  (e.g. `- bin/ci (exit 0, <n> examples, 0 failures)`).

**Local toolchain.** Ruby comes from `.ruby-version`. If `ruby -v` does not print
that version, the developer's version manager needs an exec wrapper in front of
every `ruby`, `bundle`, and `bin/*` command. Use it for every command you run, but
report commands as they appear in committed files (`bin/ci`,
`bundle exec rspec spec/...`), never with the wrapper or an absolute local path.
Never add `.tool-versions` or touch `.ruby-version` / `.ruby-gemset`.

**Agents.** None by default; this is one careful pass, run inline. Only when
`git diff --stat` lists more than about ten files, launch one `Explore` agent with
`model: sonnet` stated explicitly (never inherited) to map hunks to claims. Brief
it like a colleague, as `/plan` describes; the verdicts stay with you.

## 1. Resolve the target and base

Interpret `$ARGUMENTS`:

- **Numeric** or **GitHub PR URL** → that PR:
  `gh pr view <n> --json number,title,headRefName,baseRefName,body`.
- **Branch name** → that branch.
- **Empty** or `current` → the current branch (`git branch --show-current`).
- `--base <branch>` anywhere → the base.
- Remaining text containing a `Claims (base:` line → a supplied claims block.

Resolve the base in this order, each step falling through quietly:

1. `--base <branch>` from the arguments.
2. The `Claims (base: <base>)` line of the target's newest commit:
   `git log -1 --format=%B <branch> | grep -m1 '^Claims (base:'` (`/work` writes
   it there, so a base given to `/work` survives).
3. `gh pr view <branch> --json baseRefName -q .baseRefName` (no PR, no `gh`, or
   no network → empty).
4. `git config review.base` (see `CLAUDE.md`, **Git & PRs**).
5. `main`.

Say which target and which base you resolved, and which step gave the base.

## 2. Check out the target and record the starting state

1. Run `git status --short` and `git branch --show-current`; keep both. If a
   tracked file is modified or staged, stop and ask for the work to be committed
   or set aside (never a bare `git stash`). Untracked (`??`) entries are recorded
   and left alone.
2. If the target is not checked out, `git switch <branch>` (`gh pr checkout <n>`
   for a PR). If the switch is refused, stop and say what is in the way.
3. Run `git diff --stat <base>...<branch>` and
   `git diff --name-only <base>...<branch>`; if both are empty, there is nothing to check.

## 3. Find the claims block

Take the first of these that exists:

1. The PR body: `gh pr view <n> --json body -q .body`.
2. The newest commit message on the branch with a `Claims` section:
   `git log <base>..<branch> --grep='^Claims' --format=%H -n 1`, then
   `git show -s --format=%B <sha>`.
3. Text supplied in the arguments.

If none exists, record a 🟠 finding ("no claims block"), derive the claims from
the diff — one per observable behavior — and label each **author-unstated**. The
rest of the pass is the same. If the block's `base:` differs from the resolved
base, note it (🟡) and use the resolved one.

## 4. Check claims against the diff

- Every path under "Files changed" is in `git diff --name-only <base>...<branch>`,
  and every path there is under "Files changed". A path missing either way is 🟠.
- Read `git diff <base>...<branch>`. Every claimed behavior maps to a hunk, and
  every hunk maps to a claim (a spec hunk maps to the claim it verifies). An
  unclaimed change is 🟠: name the file and what the hunk does.
- A claim with no "Verified by" stays unverified unless step 5 or 6 proves it.

## 5. Run the gate and exercise each claim

1. Run `bin/ci`; record the exit code and RSpec's `<n> examples, <n> failures`
   line. A red gate is 🔴: still run step 7's static checks, but skip step 6
   (mutating a red suite proves nothing). If "Commands run" claims a different
   example count, note it (🟡).
2. Run each claim's named spec on its own: `bundle exec rspec <file>`, narrowed
   with `-e "<example name>"` when it names one. "All examples were filtered out"
   means the named example does not exist, so the claim is unverified.
3. When the claim is user-facing, confirm what the view emits: a request spec
   asserting with `assert_select` or `response.parsed_body` (Capybara matchers are
   not available there), or the running app:
   - `bin/rails db:seed` (idempotent; refreshes relative dates), then `bin/dev` in
     the background; the port is on Puma's "Listening on" line. Sign in as a
     seeded user (`db/seeds.rb` lists them and the shared password).
   - Delete any rows you create. Stop the server by its listening socket only:
     `lsof -nP -iTCP:<port> -sTCP:LISTEN -t`, then `ps -o ppid=,command= -p <pid>`;
     `kill -TERM <ppid>` only once that parent's command is `foreman`. A bare
     `lsof -ti tcp:<port>` can return a client socket owned by another app.

If no committed spec covers a user-facing claim, you may write a throwaway probe
spec under `spec/requests/` to confirm it; delete it in step 8 and report the
missing proof as 🟠.

## 6. Mutation pass

Specs that only post params never pin the view, and a builder's own mutations
tend to confirm what it already tested. For each claim, break **what the user
needs**, not what the author wrote, and confirm a spec fails.

| The claim depends on | Mutation |
| --- | --- |
| A `button_to` (e.g. the toggle in `app/views/tasks/_task.html.erb`) | Delete its `method:` |
| A form (`app/views/tasks/_form.html.erb`) | Remove the field or its label |
| A rendered collection | Drop its `includes` (`load_tasks` also serves `create`'s failure path) |
| "Today", "tomorrow", a date window | Swap `Date.current` for `Date.today` |
| A rule | Remove the validation, scope condition, `before_action`, `null: false`, or default |
| A branch in the code | Invert the conditional |
| A list | Return an empty collection (`Task.none`) |

For each mutation: make the smallest edit that breaks it, in one file; run the
spec that should catch it (`bundle exec rspec <file>`, then `bundle exec rspec` if
that stays green); restore with `git checkout -- <file>` and confirm
`git status --short` matches step 2's record. A `null: false` or default lives in
the database: mutate its line in `db/schema.rb` (the test database reloads a
changed schema on the next `bundle exec rspec`), and run the spec once more after
restoring so the test database is back on the real schema.

A claim whose mutation leaves the suite green is **unverified** (🟠), and its
verdict names the surviving mutation — e.g. "dropping `includes(:assignee)` from
`@due_soon_tasks` left the suite green". Specs frozen at noon UTC cannot see a
`Date.today` mutant; the "when the app's date is ahead of the server's" examples
in `spec/models/task_spec.rb` are the pattern that catches it.

## 7. Check for unwanted side effects

Each check gives what counts as a failure, its severity, and its command. Skip a
finding only when the requirement called for the change (cite the claims line).

- **Schema drift** (🟠): a table, column, index, or `version:` that no migration on
  the branch introduces. Compare `git diff <base>...<branch> -- db/schema.rb` with
  `git diff --name-only <base>...<branch> -- db/migrate`.
- **Gem churn** (🟠): any change the requirement did not call for.
  `git diff --stat <base>...<branch> -- Gemfile Gemfile.lock`
- **Files outside the area** (🟠): any path listed, including notes or handoff files.
  `git diff --name-only <base>...<branch> -- config/environments bin .claude .ruby-version .tool-versions .ruby-gemset tmp log app/assets/builds`
  `git diff --name-only --diff-filter=A <base>...<branch> | grep -vE '^(app|db|lib/tasks|spec)/'`
- **Seeds**: the gate's "Tests: Seeds" step red (🔴); a `title:` on a `-` line of
  `git diff <base>...<branch> -- db/seeds.rb` with no matching `+` line (🟠) —
  titles are the seed key, so a rename leaves the old row in every seeded database.
- **Existing examples edited or deleted** (🟠): any line the claims do not explain.
  `git diff <base>...<branch> -- spec/ | grep -E '^-\s*(it|describe|context) '`
- **Existing behavior changed**: a removed `before_action`, or `permit` gaining
  columns beyond the feature's own (🔴); a route removed, or an existing redirect
  or ordering changed (🟠).
  `git diff <base>...<branch> -- config/routes.rb app/controllers | grep -E '^[-+].*(resource|root|before_action|permit|redirect_to|order)'`
- **Seed or order dependence** (🟠): a new example that loads seeds; any failure in
  random order (confirm with the printed `--seed`).
  `git diff <base>...<branch> -- spec/ | grep -n '^+.*load_seed'`, then
  `bundle exec rspec --order rand`
- **Commits on `main` or the base** (🔴): any commit from this work (same
  subject, same files) in `git log --oneline $(git merge-base <base> <branch>)..<base>`,
  or the same with `main`.
- **Local toolchain in committed text** (🟠): any hit; one in a file the branch did
  not change is pre-existing (🟡). Run as one command, since shell variables do not
  persist between calls. The pattern is written so it cannot match itself.

  ```bash
  pattern='\b(mise|asdf|rbenv) exec\b|/(Users|home)/'
  git grep -n -E "$pattern" <branch> -- .
  git log <base>..<branch> --format=%B | grep -n -E "$pattern"
  ```

- **New N+1 on the index** (🟠): a `users_queries_during` guard failing, a
  collection newly rendered on the index with no guard that creates its rows, or
  step 6's `includes` mutation surviving.
  `bundle exec rspec spec/requests/tasks_spec.rb -e "does not query users once per"`
- **Empty failure path** (🟠): a `save`/`update`/`destroy` in a changed controller
  with no `else` that renders with `status: :unprocessable_content` or redirects
  with an alert. Read each file in
  `git diff --name-only <base>...<branch> -- app/controllers`; then
  `git grep -n unprocessable_entity <branch> -- app` must print nothing.
- **Test pollution** (🟡): a committed probe spec (🟠); time frozen any way but
  `travel_to` from `spec/support/time_helpers.rb`; a new reader of
  `ActionMailer::Base.deliveries` that does not clear it in `before`.
  `git diff --name-only --diff-filter=A <base>...<branch> -- spec/` against "Files changed"
  `git diff <base>...<branch> -- spec/ | grep -nE '^\+.*(deliveries|allow\((Date|Time)\)|before\(:all\))'`

## 8. Restore and confirm

- Every mutated file restored with `git checkout -- <file>`; probe specs deleted
  (they are untracked, so `git checkout` leaves them); development rows you
  created deleted; `bin/dev` stopped as in step 5.
- `git status --short` matches step 2's record exactly. If step 2 switched
  branches, `git switch` back to the one you started on.
- If anything cannot be restored, say so at the top of the report.

## 9. Report

Keep `/review`'s collaborative tone: what you ran, what you saw, what would fix it,
and which claims held up well. List the findings from steps 3–7 🔴 first, then 🟠,
then 🟡 ("None." if there are none). Print only the verdict line that applies.

```markdown
## QA — <PR #n or branch> (base: <base>)

| # | Claim | Evidence | Verdict |
| --- | --- | --- | --- |
| 1 | <claim, as written> | `bundle exec rspec <file> -e "<example>"` passes; <mutation> → <n> failures | verified |
| 2 | <claim> (author-unstated) | named spec passes; <mutation> → suite green | 🟠 unverified — <mutation> survived |

### Findings
- 🔴 **<title>** — `file:line` — <what is wrong>, found by `<command>`. <what would fix it>
- 🟠 **<title>** — ...
- 🟡 **<title>** — ...

### Commands run
- `bin/ci` — exit <code>, <n> examples, <n> failures
- `bundle exec rspec <file> -e "<example>"` — <n> examples, <n> failures
- Mutation: <edit> in `<file>` → `bundle exec rspec <file>` <n> failures; restored
- `git status --short` — matches the starting state

**Verdict: PASS** — every claim verified; nothing 🔴 or 🟠.
**Verdict: FAIL** — <n> unverified claims, <n> 🔴, <n> 🟠.

`/qa` checks that the work does what it claims without collateral damage;
run `/review <branch>` to judge code quality.
```
