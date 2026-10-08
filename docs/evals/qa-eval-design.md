# Measuring `/qa`: an eval design

`/qa` (`.claude/skills/qa/SKILL.md`) takes a branch and its claims block and
answers one question: does the work do what it claims, without collateral
damage? "Works" therefore means four things, and the eval measures each:

1. It **catches** what is wrong: a planted side effect, a claim no spec pins.
2. It **stays quiet** on clean work: no findings on a branch with nothing wrong.
3. It **reports truthfully**: the commands it lists were run, the verdict table
   matches what the transcript shows, every finding cites a command and a path.
4. It **leaves no trace**: the checkout, branch, and test database end as they
   started.

This document covers the three questions Tern asked (inputs, good output,
regressions after a prompt change), then the trade-offs. It is a design, not
a framework; the one runnable piece is the ruby_llm sample under `evals/`.

## 1. Inputs

A fixture is four things: a **base SHA** to start from, a **patch** for the
branch under test (`git format-patch <base>..<branch>`), the **arguments**
(`/qa <branch> --base <base>`), and an **`expect.yml`** of facts the output
must contain or avoid. Fixtures are cut from real branches, not written by
hand, so the diffs look like what `/qa` meets in practice.

| # | Fixture | Source | Expected |
| --- | --- | --- | --- |
| F1 | Clean branch | The first dogfood run of `/work`: NOT NULL on `tasks.title` (migration, schema, one model example, claims block in the commit body) | PASS; three claims verified; Findings "None." |
| F2 | Planted side effects | F1 plus a stray `.tool-versions` and `t.string "priority"` in `db/schema.rb` with no migration, amended into the same commit | FAIL; both paths named; claim 2 unverified because its "only the version bump" statement is now false; nothing else flagged |
| F3 | False claim | F1 with the model example deleted but the claim kept | FAIL; claim 1 unverified via "named example does not exist" |
| F4 | Unverified by mutation | A view claim whose spec posts params only (the toggle examples before their `_method` assertions were added) | FAIL; 🟠 unverified; the surviving mutation named (`method:` deleted) |
| F5 | No claims block | F1 with the commit body stripped | FAIL on the 🟠 "no claims block" alone; claims derived, labelled author-unstated, and all verified |
| F6 | Weak assertions | The seeded-titles example that checks 2 of 20 titles; the "keeps the current assignee" example that passes against a no-op update | 🟠 unverified for each (`.limit(6)` and a no-op `update` survive) |
| F7 | Missing companion | The area 4 skill commits as they landed, before the README entry for `/work` and `/qa` was added in a later commit | FAIL; one 🟠 "missing companion change" naming `README.md`; nothing else flagged |

F1 and F2 exist today as `cselmer/tasks-title-not-null` and
`cselmer/tasks-title-not-null-planted`. F7 is a real miss, not a plant: the
skills shipped without their README entry, and no check could see an absence. F3–F6 are one commit each away from
F1 or from session 1's branches. Later fixtures add one per side-effect class
the skill lists: a `Gemfile` bump, a widened `permit`, a dropped
`before_action`, a removed route, a renamed seed title, an empty failure path,
a local path in a commit message.

**Keeping fixtures fresh.** Every run starts by `git worktree add` at the base
SHA and `git apply --check` of the patch; when the app moves on, the apply
fails loudly, which is the cue to re-cut the fixture (or retire it). Keep the
set small (under ten), each with a one-line reason it exists, and retire a
fixture when its check moves into a hook: the status-first hook under
`.claude/hooks/` already covers what a status-first fixture would.

**For comparison, `/work` fixtures** would be requirements rather than
branches: the NOT NULL requirement (expected diff shape known), an ambiguous
one ("make tasks sortable": assumptions stated, not a stall), and a scope-creep
bait. `/qa` is the better first target because its inputs and expected
outputs are both concrete.

## 2. What good output looks like

Deterministic checks come first and own the gate. The judge only extracts
facts for the parts that need reading.

### Deterministic checks (Ruby, over the transcript and the worktree)

| Check | How |
| --- | --- |
| Verdict present once and correct | Exactly one `**Verdict: PASS**` or `**Verdict: FAIL**` line; matches `expect.yml` |
| Sections present, in order | QA heading, verdict table, Findings, Commands run, verdict, closing `/review` line |
| Planted paths named | Each path in `expect.planted` appears in Findings |
| Quiet on clean work | For F1: Findings is "None.", no 🔴/🟠/🟡 anywhere |
| Commands claimed were run | Every command under "Commands run" matches a Bash tool call in the transcript, ignoring the local toolchain prefix; `bin/ci` and at least one `bundle exec rspec` appear |
| Gate result honest | The `<n> examples, <n> failures` in the report equals RSpec's line in the transcript |
| Nothing left behind | After the run: `git status --short` equals the start, `git diff` empty, `git branch --show-current` unchanged, no new commits, test schema restored (`bundle exec rspec spec/models` green) |
| Budget | Under `max_turns` and the cost ceiling; wall time recorded |

### LLM judge: extraction, not scoring

The judge (Haiku 5.5 by default) reads the report and the diff and fills a
fixed schema; Ruby compares the schema with `expect.yml`. Asking for checkable
facts keeps the judge away from "is this good?" questions it answers with
confidence rather than accuracy.

```yaml
claims:
  - claim: string
    verdict: verified | unverified
    evidence_names_spec_or_command: boolean
    mutation_named: boolean
side_effects:
  - path: string
    severity: 🔴 | 🟠 | 🟡
    command_cited: boolean
unsupported_findings: [string]   # findings that point at nothing in the diff
assumptions_addressed: boolean   # the block's Assumptions were checked, not skipped
rationale: string
```

As `RubyLLM::Evaluation` criteria (`evaluation :name, "statement", minimum:`):

- `grounded`: every finding cites a command and a path that is in the diff.
- `accurate_table`: each claim's verdict equals the fixture's known truth.
- `restored`: the report states the restore and the transcript shows it.
- `no_padding`: on the clean fixture no finding is raised.

Calibrate the judge once: hand-label 10–20 transcripts (including two written
to talk the judge into a pass) and measure agreement per criterion. Redo it
when the judge model changes.

## 3. Catching a regression after a prompt change

**Baseline.** Run every fixture N=5 times on the current `SKILL.md`; store per
fixture the pass rate, tokens, cost, and wall time (`Report#to_h` from
ruby_llm, or `aggregate-result.json` from `claude plugin eval`). Pin the
subject model, judge model, and effort in the record. A model bump is a new
system: re-baseline, do not compare.

**Trigger.** Any change to `.claude/skills/qa/SKILL.md`, `CLAUDE.md`,
`.claude/agents/*.md`, `.claude/hooks/*`, or `.claude/settings.json`. Run by
hand (`ruby evals/run.rb` today; `bin/rails ruby_llm:eval` once the gem is in
the `Gemfile`; or the `claude plugin eval` command below), or as an opt-in
`bin/ci` step: `step "Evals", "..." if ENV["EVALS"]`. Never in the default
`bin/ci`: it costs money, needs a key, and is not deterministic.

**Gates.**

- Must-pass fixtures (F1 clean, F2 planted) gate at N/N. A single miss blocks.
- Measured fixtures (F3–F6, judge criteria) alert on any drop against the
  baseline and are re-run at 2N before the prompt is blamed; an 80%-reliable
  case scores 3/5 or worse in about a quarter of 5-run batches.
- Cost: alert when cost per run rises more than 30%. Doubled tokens is a
  regression even when every verdict is right.

**Runners, from cheapest to most faithful.**

1. **Prompt-level, `RubyLLM::Evaluation`** (seconds, cents). `perform` pastes
   the skill text, `CLAUDE.md`, the diff, and the claims block into one
   message and asks for the report. No tools, so it cannot run the gate or
   mutate; it measures the reasoning about claims versus diff and the
   side-effect checks that read the diff (schema drift, stray files, widened
   params). This is the inner loop for prompt edits, and the judge for the
   other two runners. The sample under `evals/` is this shape, pointed at
   `review-rails` because that agent runs as a single call today; swapping
   the dataset and `perform` makes it the `/qa` prompt-level eval. Rules from
   the research: never `with_temperature` (the 5.5 models reject it); pin
   model IDs, `with_thinking(effort:)`, and `with_max_output_tokens`; measure
   the remaining variance with `repetitions:`; `minimum:` per criterion sets
   the threshold; the RSpec adapter (`evaluates described_class`, tagged
   `:eval` and excluded by default) and the `ruby_llm:eval` rake task exit
   non-zero on failure.
2. **End-to-end, `claude plugin eval`** (Claude Code 2.1.285). Cases live at
   `.claude/skills/qa/evals/<case>/prompt.md` with `graders/*.md`
   (`type: llm` for the schema above, deterministic graders for the table in
   §2) and a `scaffold_script` that adds the worktree at the base SHA, applies
   the patch, and runs `bin/setup --skip-server`. Run with `--runs 5 -j 2
   --judge-model claude-haiku-5-5 --threshold 1.0 --max-cost-usd 10
   --no-publish --scaffold --allow-tools Bash Edit Write`. The default
   `--ablation with-without` adds a no-skill arm: the same prompt without
   `/qa` loaded. The delta is the skill's measured value, and the arm that
   reads a bare "check this branch" and finds the plants anyway tells you a
   fixture is too easy.
3. **End-to-end, `claude -p`**, when the plugin-eval sandbox cannot reach
   Postgres: per fixture, `git worktree add` + apply, then
   `claude -p "/qa <branch> --base <base>" --output-format stream-json
   --verbose --model claude-sonnet-5-5 --max-budget-usd 2
   --no-session-persistence`, grade the transcript and worktree with the §2
   checks and the judge, drop the worktree. Databases come per worktree from
   `config/database.yml`, so runs can go in parallel.

**Evidence from the first fixtures.** The two `/qa` runs behind F1 and F2 are
the baseline's first data points: each used about 87k tokens on Sonnet 5.5
and finished in under three minutes, running `bin/ci`, two mutations, and
every side-effect command. The `/work` run that produced F1 used about 85k.
Those numbers set the cost line in §4.

### Running the sample

`evals/run.rb` is the prompt-level runner from the research, kept small on
purpose: `bundler/inline` pulls ruby_llm 2.1 and minitest, so the `Gemfile`
is untouched and `bin/ci` ignores it apart from `standardrb`.

```
ruby evals/run.rb --dry-run        # prints the prompts, calls nothing
ANTHROPIC_API_KEY=... ruby evals/run.rb
EVAL_REPETITIONS=3 ANTHROPIC_API_KEY=... ruby evals/run.rb
```

It grades the `review-rails` prompt on two fixture diffs (one with empty
failure branches, one handled), first with regex assertions from
`cases.yml`, then with a Haiku judge on two criteria, and writes a JSON report
to `tmp/evaluations/`. Two cases cost a few cents. It has been run against a
stub API and in dry-run mode in this repo; the first live run waits for an API
key, which Tern has offered for the interview.

## 4. Trade-offs, plainly

- **Nondeterminism.** Temperature cannot be pinned on the 5.5 models, so
  every number is a rate, not a bit. N runs cost N times as much, and
  thresholds must leave room for noise; the must-pass set is small for that
  reason.
- **Judge bias and self-grading.** Claude grading Claude shares its blind
  spots and rewards confident prose. That is why the deterministic checks own
  the gate, the judge only extracts facts into a schema, Haiku grades Sonnet
  only after calibration against human labels, and the clean fixture exists
  to catch a judge that praises padding.
- **Fixture staleness and overfitting.** Pinned patches fail loudly, which is
  good, but planted defects are easier than real ones and a prompt tuned to
  them learns the plants. Hold two fixtures back from anyone editing the
  skill, and cut new fixtures from real review findings (session 1's 🟠 list
  is the best source) rather than from imagination.
- **Headless versus interactive.** Prompt-level runs skip the harness, the
  tools, and the gate; `claude -p` and `claude plugin eval` skip the person.
  `AskUserQuestion` never fires, so only the non-interactive path is
  measured. Say so in the report; do not read a headless pass as "works with
  a person steering".
- **Cost.** Prompt-level runs cost cents; end-to-end runs dominate: fixtures ×
  N × runners. At the measured 87k tokens per `/qa` run, six fixtures at N=5
  is about 2.6M tokens per suite run on Sonnet, on the order of ten to twenty
  dollars. The cheaper the check, the earlier it should move out of the eval
  and into a hook or a spec; evals measure what mechanical checks cannot.

## Open questions for Tern

1. What effort level do skills run at inside Claude Code? The sample pins
   `high`; the baseline must match.
2. Is Haiku a strong enough judge for extraction, or should the judge be
   Sonnet with Haiku as a cheap first pass?
3. Can the `claude plugin eval` sandbox reach a local Postgres? If not, runner
   3 is the end-to-end path.
4. Budget for a live demo on Tern's API key: one prompt-level run of the
   sample is under a dollar; one end-to-end suite run is tens of dollars.
