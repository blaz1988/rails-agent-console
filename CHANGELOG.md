# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add opt-in schema diagnostics via `ai_schema(diagnostics: true)` for model and association inspection failures.

## [0.1.0] - 2026-09-29

First public release.

### Console helpers

- `ai "..."` proposes one ActiveRecord query from a plain-English question, shows it with a
  short explanation and its assumptions, and runs it only after confirmation.
- `ai! "..."` allows a single write. Destructive calls report the rows they would touch and
  need a typed confirmation word.
- `ask "..."` answers a question without running anything. A question about "that query" or
  "the last one" is sent together with the session's recent queries.
- `explain`, `run`, `ai_schema`, `ai_history`, `ai_reset` and `ai_model`.
- Follow-ups that refer back ("them", "those", "their", and the Croatian "ih" and "njih")
  build on the previous query instead of starting over.
- Installed as IRB helper methods on Rails 8 and into `Rails::ConsoleMethods` on Rails 7.

### Schema context

- Built from `ActiveRecord::Base.descendants`: columns, types, nullability and every
  association, including `through:`. Models relevant to the question are described in full
  and the rest are listed by name, about 1,700 tokens for a whole question on an 18-model app.
- Only the shape of the application is sent to the model, never its data.

### Safety

- Generated code is parsed with `Ripper` and checked call by call. Read-only by default, with
  an allowlist plus the application's own columns and associations.
- Always refused, even in write mode: `connection`/`execute`, `send`, `eval`, `system`,
  backticks, `File`, `Kernel`, `ENV`, definitions, instance and global variables, mutating or
  chained raw SQL, and credential columns such as `password_digest`.
- Generated code runs in a binding of its own, with a timeout.

### Corrections made in code, before a query runs

- Joins the association cannot build are written out in SQL; association names used as table
  names inside SQL are replaced with the table.
- Ambiguous columns in joined queries are qualified with the table the query starts from,
  outside of subqueries.
- A count divided by a count is divided as decimals, so a rate is not rounded down to 0.
- `joins(search_results)` with a bare association name becomes `joins(:search_results)`.
- A range that ends on a plain date runs to the end of that day.
- "in 2025", "last month" and similar phrases are turned into exact ranges before the model
  sees the question.
- Aggregates placed before relation methods, `first` on a grouped relation, pointless
  `distinct`, raw SQL passed to `order` and `pluck` without `Arel.sql`, and broken quoting.

### Results

- A condition on a text column that compares it with a value the column never holds
  (`country: "Croatia"` where the data says `HR`) is pointed out after the query runs, with
  the values the column does hold. Those values are printed locally and never sent.
- Grouped rows and rows with computed columns are shown as their values; whole numbers from
  SQL (`EXTRACT(MONTH ...)`) are shown as integers.
- A failed query is retried with the error and a Rails-specific hint, up to
  `max_repair_attempts` times. Every retry is a new proposal with the same validation and
  confirmation.

### Providers and setup

- OpenAI, Anthropic, Gemini and Ollama over `net/http`, any OpenAI-compatible endpoint through
  `api_base`, or any callable through `config.client`.
- A guided setup on first run, in `ai_model` and in `rails-agent configure`: where the model
  runs, the provider, the base URL, the key, a model from the provider's own list, and a live
  check before anything is kept.
- `ai_model "gpt-4o"` switches to the provider the name belongs to.
- Keys are read from the environment first, then from `~/.rails_agent_console/config`
  (mode 0600 in a 0700 directory). A key from the environment is never copied to disk.
- `rails-agent configure | doctor | schema` and a `rails_agent_console:install` generator.

[Unreleased]: https://github.com/blaz1988/rails-agent-console/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/blaz1988/rails-agent-console/releases/tag/v0.1.0
