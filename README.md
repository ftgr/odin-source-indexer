# odin-source-indexer

A source indexer and lexer for [Odin](https://odin-lang.org/), written in Odin.
The goal is to answer questions like *"where is this symbol declared?"* from the
command line, without running the compiler or a language server.

This is a personal learning project for Boot.dev's Personal Project 1, built in
public one milestone at a time.

## Status

Milestones 0–6 are complete: `tokens <file>` prints one token per line as
`line:column kind text`, covering identifiers, keywords, operators, punctuation,
numeric literals (including `0h` hex floats), interpreted, raw, and
triple-quoted strings, and rune literals. Line comments and nested block comments
are skipped by default; the lexer can retain them as `Comment` tokens. Positions
are 1-based, columns count runes, tabs count as one column, and CRLF counts as
one line break. `symbols <file-or-dir>` lists top-level declarations as
`file:line:column<TAB>kind<TAB>name`, including packages, imports, procedures,
structs, unions, enums, bit sets, types, constants, and variables. Directories
are walked recursively with two arenas (long-lived index, per-file scratch) and
counters go to stderr. `--json` and stable output ordering are still planned.
See [`GUIDE.md`](GUIDE.md) for the plan.

## What it does

Today the CLI validates a command, prints usage, dumps the token stream for
`tokens`, and indexes top-level declarations for `symbols`. As the milestones
land it will:

- `symbols <file-or-dir>` — list declarations (packages, imports, procedures,
  structs, unions, enums, bit sets, types, constants, variables) with file, line,
  and column, walking directories recursively. `--json` (M7) is planned.
- `tokens <file>` — dump the lexer's token stream, one token per line.
- Serve the same answers over JSON-RPC for editor integration (later).

Contract: stdout is data only (safe to pipe) and diagnostics go to stderr.
Exit `0` means the requested output is complete, `1` means the input could not be
read or `symbols` found nothing to print, and `2` is a usage error. A malformed
literal becomes an `Invalid` token and is reported once as
`file:line:column: error` on stderr, while the rest of the file is still
tokenized.

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
| `symbols <file-or-dir>` | List declarations as `file:line:column kind name` (`--json` planned) |
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
src/commands.odin           read_source, count_lines, tokens and symbols commands
src/lexer/                  token model, cursor, and lexer
src/index/                  symbols, extraction, directory walk, and arenas
testdata/                   sample inputs for tests
tools/fmt-check.sh          format drift check (odinfmt has no --check)
GUIDE.md                    milestones M0–M12 and design notes
```

## License

No license has been chosen yet.
