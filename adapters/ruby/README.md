# `adapters/ruby/` — mutant-rspec as the on-demand mutation diagnostic

A worked wiring of the engineering article's **mutation decision** for a
Ruby/RSpec project, extracted from a real consumer bootstrap (the kit's issue
#85). The node-ts adapter answers the same question for a pnpm/TypeScript
monorepo with Stryker; this one exists so a non-JS stack has a second shape to
triangulate from. The adapters rule applies unchanged: **copy from this only
if your stack matches it; otherwise read it for the shape and write your
own.**

What "wired" means here, per shared invariant §9: the tool runs **on demand,
never as a gate**. Surviving mutants are the objective form of "this test
enforces nothing" — a diagnostic you read, not a threshold that blocks a
push.

## The wiring

1. Gemfile, test group:

   ```ruby
   gem "mutant-rspec"
   ```

2. Copy `mutant.yml.example` to your repo root as `.mutant.yml` and edit the
   marked lines (requires, includes, subjects). The example records each
   key's reason inline.

3. The on-demand commands — full sweep, and the differential form that plays
   the same role as the node-ts adapter's `mutation-delta.sh`:

   ```sh
   bundle exec mutant run                       # everything the matcher names
   bundle exec mutant run --since main          # only what changed vs main
   ```

   The `--since` form is the one a review cites: it scopes the diagnostic to
   the diff under review, which is what makes it cheap enough to actually
   run. (mutant ships incremental runs natively, so this adapter needs no
   delta script of its own — read `adapters/node-ts/mutation/` for what that
   machinery looks like when the tool does not provide it.)

4. Licensing: mutant is commercial software that is **free for open-source
   projects** — the `usage: opensource` key in the config is that
   declaration. A private repo needs a paid licence key instead; decide this
   when you fill the article's mutation-decision line, not when the first
   run refuses to start.

5. Record the outcome in `constitution/local-engineering.md`'s
   **Mutation decision** line: the tool and the on-demand command, e.g.
   `mutant-rspec — bundle exec mutant run --since main`.

## Field notes — read these before you trust a low score

Both were found wiring this into a real project, where the first full run
reported **1.5% mutation coverage** on a healthy test suite. Neither number
was about the tests:

- **Methods defined inside a `Data.define do … end` block are invisible to
  mutant's kill loop.** The same applies to `Struct.new do … end`. mutant
  mutates the method as defined on the generated class's instance, but the
  block-defined methods a value object exposes are frequently exercised
  through a frozen instance the specs build once — the mutation lands on a
  copy of the method the test path never re-resolves, so every mutant
  "survives". Define behavior-bearing methods in an ordinary
  `class X < Data.define(...)` reopening instead of the block form, and the
  numbers become honest.
- **`module_function` methods double the same way.** `module_function`
  creates two copies of each method — the private instance method and the
  module's singleton method. mutant mutates the instance copy; a spec that
  calls `MyModule.helper` exercises the singleton copy, so the mutation is
  never seen and the mutant survives. Use `def self.helper` (or
  `extend self`) for module APIs you intend to mutation-test.

The general lesson both instances teach: **a surviving mutant means the test
never saw the mutation — and "the test is weak" is only one of the reasons it
might not have.** Rule out the definition-copy traps above before rewriting
healthy specs.

## What is verified, and what is not

`tests/adapters-demo.sh` holds this directory to the same two claims as its
siblings: the files are well-formed and present (including both field notes
above — losing them is a suite failure, because the notes are the value), and
bootstrap delivers the tree to a consumer byte-identical and dormant. What no
kit suite can prove: an actual mutant run, which needs a Ruby project. The
example config is transcribed from a working consumer setup; verify the keys
against the mutant documentation for the version you install.
