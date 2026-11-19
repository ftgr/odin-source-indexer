# odin-source-indexer

A source indexer and lexer for [Odin](https://odin-lang.org/), written in Odin.
The goal is to answer questions like *"where is this symbol declared?"* from the
command line, without running the compiler or a language server.

This is a personal learning project for Boot.dev's Personal Project 1, built in
public one milestone at a time.

## Status

Milestone 0 (CLI skeleton, strict build/test gates), Milestone 1 (token model),
and Milestone 2 (lexer core) are complete: `tokens <file>` prints one token per
line as `line:column kind text`, covering identifiers, keywords, operators, and
punctuation. Numbers and quoted literals arrive in Milestone 3, comments in
Milestone 4. `symbols` is still a placeholder. See [`GUIDE.md`](GUIDE.md) for the
plan.

## What it does

Today the CLI validates a command, prints usage, and dumps the token stream for
`tokens`; `symbols` is still a placeholder. As the milestones land it will:

- `symbols <file-or-dir>` — list declarations (packages, imports, procedures,
  structs, unions, enums, bit sets, types, constants, variables) with file,
  line, and column.
- `symbols --json` — the same data as a stable JSON envelope for editors and
  scripts.
- `tokens <file>` — dump the lexer's token stream, one token per line.
- Serve the same answers over JSON-RPC for editor integration (later).

Contract: stdout is data only (safe to pipe), diagnostics go to stderr, and
exit codes are meaningful (`0` success, nonzero failure).

## Clone and run

```sh
git clone https://github.com/ftgr/odin-source-indexer.git
cd odin-source-indexer

make build
./out/debug/odin-source-indexer help

# or build and run in one step
make run
```

The debug build is the development default; `make release` produces an
optimised binary in `out/release/`.

## Requirements

- [Odin](https://odin-lang.org/docs/install/) `dev-2026-10` or newer, on `PATH`
- `odinfmt` (only needed for `make fmt` and `make verify`)
- GNU make, on Linux

## Commands

| Command | Purpose |
| --- | --- |
| `symbols <file-or-dir> [--json]` | Index declarations (planned) |
| `tokens <file>` | Dump the token stream as `line:column kind text` |
| `help`, `-h`, `--help` | Show usage |

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
src/main.odin               CLI entry point, logging and leak tracking
src/helpers.odin            command validation and usage
src/commands.odin           read_source, count_lines, tokens command
src/lexer/                  token model and lexer (in progress)
src/index/                  symbol index (in progress)
testdata/                   sample inputs for tests
tools/fmt-check.sh          format drift check (odinfmt has no --check)
GUIDE.md                    milestones M0–M12 and design notes
```

## License

No license has been chosen yet.
