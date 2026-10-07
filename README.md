# README

This application is intended to serve as the starting point for a basic
pair programming interview.

## Setup

### PostgreSQL

We use PostgreSQL as our primary persistence store. On Mac OS, use [Homebrew](https://brew.sh)
to install the latest PostgreSQL version.

```
brew install postgresql@18
brew services start postgresql@18
```

### Ruby Version & Gems

We use a `.ruby-version` and `.ruby-gemset` file to indicate to your local
Ruby version manager the correct version of Ruby to use. Refer to those files
if you're manually managing your Ruby installation.

To install Rubygem dependencies, use Bundler:

```
bundle install
```

### Bootstrapping

`bin/setup` is the first command to run in any fresh checkout:

```
bin/setup
```

It installs the Rubygem dependencies, creates and seeds the database, and
builds the Tailwind CSS bundle. The seeds include several users you can use to
log in. Refer to `config/database.yml` for details on the local database name
and connection information.

### Running the Tests

```
bundle exec rspec
```

After `bin/setup`, the suite rebuilds the Tailwind CSS bundle if it goes
missing, for example after `git clean -fdx`. `bin/rails spec` builds it
unconditionally via `spec:prepare`.

### Local Development

Since we use the `tailwindcss-rails` gem to pull in the [Tailwind CSS library](https://tailwindcss.com),
the local development environment requires two separate process: the normal
Rails server process and a local Tailwind process. To start them, run:

```
bin/dev
```

## Claude Code

This repo includes custom [Claude Code](https://claude.com/claude-code) tooling
under `.claude/`. If you use Claude Code in this project, the following slash
commands are available to everyone who clones the repo.

### Skills

- **`/plan [task description]`** — Plans the implementation approach before any
  code is written. It enters Plan mode (read-only), explores the codebase, and
  presents an approach for your approval. Use it before starting non-trivial work.
- **`/review [PR number, GitHub URL, or branch — omit for current branch]`** —
  Runs a multi-agent code review. It routes the diff to focused review agents,
  synthesizes their findings by severity (🔴 / 🟠 / 🟡), and can post the result
  as a PR comment.

### Review agents

`/review` is backed by a handful of focused agents in `.claude/agents/`, each
applying one lens to the change:

- **`review-rails`** — correctness, bugs, and idiomatic Rails conventions.
- **`review-security`** — authentication, authorization, mass assignment, and injection.
- **`review-simplicity`** — over-engineering, duplication, and dead code (YAGNI).
- **`review-testing`** — RSpec/FactoryBot coverage and test quality.

See [`CLAUDE.md`](CLAUDE.md) for the code conventions these tools enforce.
