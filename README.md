# odin-source-indexer

A source indexer and lexer for [Odin](https://odin-lang.org/), written in Odin.
The goal is to answer questions like *"where is this symbol declared?"* from the
command line, without running the compiler or a language server.

This is a personal learning project for Boot.dev's Personal Project 1, built in
public one milestone at a time.

## Status

Early development. The CLI skeleton and the strict build/test gates are in place
(Milestone 0); `symbols` and `tokens` currently print placeholders. The lexer
and indexer arrive in Milestones 1–7. See [`GUIDE.md`](GUIDE.md) for the plan.

> **Naming:** the repository is `odin-source-indexer`; the build artefact still
> carries the original working name `odin-lens`.

## What it will do

- `symbols <file-or-dir>` — list declarations (packages, imports, procedures,
  structs, unions, enums, bit sets, types, constants, variables) with file,
  line, and column.
- `symbols --json` — the same data as a stable JSON envelope for editors and
  scripts.
- `tokens <file>` — dump the lexer's token stream, one token per line.
- A JSON-RPC mode for editor integration is planned later.

## Requirements

- Odin `dev-2026-10` or newer
- `odinfmt` (only needed for `make fmt` and `make verify`)
- GNU make, on Linux

## Build and run

```sh
make build
./out/debug/odin-lens help

make release
./out/release/odin-lens help
```

`make run` builds the debug binary and runs it.

## Commands

| Command | Purpose |
| --- | --- |
| `symbols <file-or-dir> [--json]` | Index declarations (planned) |
| `tokens <file>` | Dump tokens (planned) |
| `help`, `-h`, `--help` | Show usage |

Contract: stdout is data only (safe to pipe), diagnostics go to stderr, and
exit codes are meaningful (`0` success, nonzero failure).

## Development

```sh
make check    # type-check with vet + strict style (fast inner loop)
make test     # one `odin test` run per package
make fmt      # format sources in place (odinfmt.json)
make verify   # fmt-check + check + tests; the pre-commit gate
make clean    # remove out/ and .cache/
```

Builds are strict: warnings are errors, unused imports/variables fail, tabs and
`strict-style` are enforced. Tests fail on leaked memory
(`ODIN_TEST_FAIL_ON_BAD_MEMORY`), so allocations must be paired with the right
allocator.

`make install-hooks` points git at the versioned hook in `.githooks/`, which
runs `make verify` before every commit.

## Layout

```
src/main.odin        CLI entry point
src/helpers.odin     command validation and usage
src/lexer/           token model and lexer (in progress)
src/index/           symbol index (in progress)
testdata/            sample inputs for tests
tools/fmt-check.sh   format drift check (odinfmt has no --check)
GUIDE.md             milestones M0–M12 and design notes
```

## License

No license has been chosen yet.
