# odin-lens — a build guide

A step-by-step plan for building a real Odin program while learning the language.
This guide contains **definitions, decisions, and acceptance criteria** — no source
code. You write every line.

A draft reference implementation exists at `../odin-lens-spoilers/src`. Don't open
it until a milestone is done and tested; then diff it against your version and read
the comments, which explain the tradeoffs. (It is intentionally unfinished and does
not compile as-is.)

---

## 0. How to use this guide

- Work one milestone at a time. Each has a **timebox**, a **definition of done**,
  and a **traps** list.
- Do not start the next milestone until the current tests pass and you have
  committed. If you get stuck for more than an hour on a trap, read the relevant
  file in `~/Code/Odin/Odin` (the standard library and compiler source is the real
  documentation).
- Every milestone ends with a short **self-check**: explain the answer out loud
  without looking at the code. If you can't, you learned syntax, not the concept.
- Verdicts in this guide were checked against **your** toolchain:
  `odin version` → `dev-2026-10`, stdlib at `/usr/lib/odin` (`odin root` prints it).

---

## 1. What you are building

**Definition.** `odin-lens` is a local code-intelligence tool for Odin source. It
reads `.odin` files and answers structural questions: *what is declared here, where
is it declared, what kind of thing is it.*

It has two surfaces:

1. **CLI (batch).** `odin-lens symbols <path>` prints declarations as text or JSON.
   Short-lived process, easy to test, easy to pipe.
2. **RPC server (long-lived).** Same answers over JSON-RPC on stdio, so an editor
   can keep an index warm instead of re-scanning on every keystroke. This is the
   shape of a language server (LSP), minus the protocol ceremony.

**Who uses it.** You, in your editor, while learning Odin. That is the point: the
tool improves exactly the workflow you are currently struggling with, so
"should I add this feature?" answers itself.

**Why this project and not another web server**

- The corpus is already on disk (`~/Code/Odin/Odin/core`, `vendor`, your own code),
  so you have thousands of real files to test against from day one.
- There is a **reference oracle**: the compiler itself (`odin check`, `odin doc`).
  You can prove your output is wrong instead of guessing.
- It forces the concepts Odin is actually about: explicit memory (arenas),
  multiple return values instead of exceptions, tagged unions, slices-as-views,
  package boundaries, no classes.

**v1 scope (what "done" means)**

- CLI with `symbols` and `tokens` commands; text and JSON output.
- Lexer that handles real Odin source without errors on the whole stdlib.
- Symbol extraction for top-level declarations, with file/line/column.
- Recursive directory indexing with bounded memory.
- Test suite that runs with `odin test`.
- A Python differential test harness that checks your output against the compiler.

**Explicitly out of scope for v1** (park these, don't creep into them)

- Full parsing / expression-level analysis. Heuristics are fine.
- Type checking, generics resolution, cross-file references.
- Incremental re-indexing (milestone 11, optional).
- Windows/macOS support. Linux only until you're bored.
- Fancy terminal UI, web UI, database, config files.

---

## 2. Skills map

| Milestone | Odin concepts exercised |
|---|---|
| M0 | packages, build modes, flags, `odin check` vs `build` vs `test` |
| M1 | enums, structs, strings vs `[]byte`, explicit allocators, multiple returns |
| M2 | slices as views, `switch` on strings, tables, byte vs rune |
| M3 | UTF-8, runes, escapes, numeric literals, cursor design |
| M4 | error values instead of exceptions, `defer`, nested comments |
| M5 | heuristic analysis, lookahead, ownership of string data |
| M6 | arenas, allocator lifetimes, iterator protocol, filesystem |
| M7 | struct field tags, JSON marshaling, sorting, CLI contracts |
| M8 | table-driven tests, golden files, corpus testing |
| M9 | (Python) subprocess oracles, differential testing, pytest |
| M10 | threads, channels/mutexes, JSON-RPC framing, long-lived state |
| M11 | profiling, allocation reduction, parallel work distribution |

---

## 3. Definitions: Odin concepts you will use

Short definitions, plus why each one matters *in this project*. Read the whole
list now — you don't need to master it, you need to recognize it when it appears.

**Package.** A directory of `.odin` files that all declare the same package name.
There is no file-level module system: everything in a directory shares scope.
Imports are directory-relative (`import "lexer"` from `src/main.odin` resolves to
`src/lexer`; from inside `src/index` you need `import "../lexer"`). *Why it
matters:* this forces the package split — lexer, index, main — early, which is
where the design actually lives.

**Build, check, run, test.** `odin build <dir>` compiles; `odin check <dir>`
type-checks without emitting a binary (fast feedback loop); `odin run <dir>` builds
and runs; `odin test <dir>` builds and runs `@(test)` procedures **in the initial
package only**. *Trap:* `odin test src` does not run tests in `src/lexer`; you must
run it per package.

**Procedure and multiple return values.** Everything is a procedure; there are no
methods, no classes, no constructors, no exceptions. A procedure can return
several values, and the idiomatic error channel is the last one. *Why:* every
I/O call in this project returns `(value, error)`.

**The `value, ok` / `value, err` idiom.** Errors are ordinary values; a call either
returns a non-nil error or a valid result. `or_return` propagates the second value
if it is non-nil; `or_else` supplies a fallback. *Why:* you will write this dozens
of times; the discipline of "handle or propagate" replaces try/except.

**`defer`.** Schedules a statement to run when the enclosing scope exits, LIFO.
Used for `os.close`, `read_directory_iterator_destroy`, arena resets. *Why:* there
is no garbage collector to close your handles, so `defer` is how resources get
released on the error path too.

**Struct.** A record. Fields can carry **tags** (string literals after the type),
which is how the JSON encoder learns field names. *Why:* the `Symbol` record's tags
define the wire format your Python side reads.

**Enum.** Named integer constants, `u8`-backed here. *Trap (verified on your
install):* a `switch` over an enum is **exhaustive** — you must list every value or
use `#partial switch`; a `case:` does not act as a catch-all for enums. This will
bite you when the OS returns file types you didn't think about. Prefer `if`/`else`
chains when you intend to ignore the rest.

**Union (tagged union).** A value that holds exactly one of several variants, with
a runtime tag you switch on. This is Odin's replacement for class hierarchies.
*Where:* in v1 the lexer only produces tokens, so unions are mostly a *future* need
(AST nodes in M12). Learn to read the syntax now, use it later.

**Slices `[]T`, dynamic arrays `[dynamic]T`, fixed arrays `[N]T`.** A slice is a
pointer plus a length; it is a **view**, not an owner. `[dynamic]T` owns a buffer
and can append (reallocating). *Why:* `Token.text` is a slice into the source
buffer. Free the source and every token's text dangles. This is the single most
important ownership rule in the project.

**String.** Immutable bytes plus a length; slicing is free and shares memory;
indexing gives bytes, not runes; concatenation allocates. *Why:* a lexer is one
long exercise in slicing without copying, and one long exercise in knowing exactly
when you must copy.

**Rune, UTF-8.** `rune` is a Unicode code point (32-bit). Source text is UTF-8, so
byte offsets and character columns disagree as soon as an identifier has `é`.
*Decision:* track **byte offset for slicing** and **rune column for display** — you
need both, and mixing them up produces off-by-N bugs that only appear on non-ASCII
files.

**Allocator and `context`.** Odin has no global `new`. Allocation is explicit:
`make`/`new` take an allocator, and `context.allocator` is the implicit one.
`context.temp_allocator` is a scratch allocator you reset manually. *Why:* this
project allocates thousands of small objects; choosing an allocator *is* the
design.

**Arena.** A bump allocator over one big buffer: allocate forward, free everything
at once, never free individually. Your install has no growing arena, so you
reserve a fixed backing buffer (a large `make` of bytes; untouched pages are not
resident). *Why:* two arenas with different lifetimes — one for the index that
lives for the process, one reset after every file — is what keeps memory flat
while indexing 10k files.

**Attributes `@(...)` and directives `#...`.** `@(test)` marks a test procedure;
`@(private)` hides a declaration from importers; `@(require_results)` forces callers
to use a return value. `#` appears in types/compile-time features (`#no_nil`,
`#caller_location`, `#partial switch`, `#force_inline`). *Why:* the lexer must
tokenize both (`@`, `#`, `$`) even though v1 doesn't interpret them.

**Parametric polymorphism `$T` and `where`.** Compile-time generics. `$` is also
the prefix for compile-time parameters in procedures. *Why:* your lexer will
eventually take an allocator parameter like the stdlib does; and `$T` shows up all
over stdlib signatures you'll read.

**`using`.** Embeds a type's fields or brings a package's names into scope. *Why:*
you'll meet it in stdlib code; don't use it in v1 — it makes ownership harder to
see.

**Implicit semicolons.** Odin inserts statement separators at newlines, like Go.
*Trap (verified):* the tokenizer still emits `:` and `=` separately, so `::` and
`:=` are **two tokens each** and the parser recombines them. Your indexer must look
for `Colon` followed by `Colon`. This is exactly the kind of thing you learn by
reading `Odin/src/tokenizer.cpp`.

**`when`.** Compile-time `if`. Not needed in v1; know it exists so you don't reach
for runtime branching where the language offers compile-time dispatch.

**vet.** `odin build ... -vet` enables extra checks: `-vet-unused`,
`-vet-unused-variables`, `-vet-unused-imports`, `-vet-shadowing`. Turn them on in
your Makefile from M0; they catch the class of bugs that make debugging slow.

---

## 4. Definitions: project terms

**Lexeme / token / kind.** A lexeme is the raw text of one lexical unit (`proc`,
`12`, `"hi"`). A token is that lexeme plus metadata (kind, byte offset, line,
column). The kind is the category (`Keyword_Proc`, `Integer`, `String`).

**Trivia.** Whitespace and comments: syntactically ignorable. *Decision:* skip
trivia by default, but keep an option to emit comment tokens — doc comments become
hover text in M12.

**Lexer / scanner.** Turns text into tokens. No grammar knowledge, no nesting of
expressions, no error recovery beyond "don't hang".

**Parser / AST / symbol table.** A parser turns tokens into a tree using a grammar;
an AST is that tree; a symbol table maps names to declarations in a scope. *v1 does
not have these.* Symbol extraction is a heuristic pass over tokens. Know the
difference — it is the difference between "works on my files" and "works".

**Symbol.** One declaration: a name, a kind, a location. For v1, top-level only.

**Index.** The collection of symbols for a set of files, plus enough metadata to
answer queries. In v1 it is an in-memory list, sorted.

**Oracle.** A trusted source of truth you compare against. Here: the Odin compiler.
*Why it matters:* it converts "I think my lexer is right" into a pass/fail signal.

**Differential testing.** Run the same input through your implementation and the
oracle; assert agreement. For a lexer, "agreement" means: *if the compiler accepts
the file, my lexer must report no errors, and the token coverage must not be
obviously wrong.* It catches whole classes of bugs that hand-written tests miss.

**Golden file.** A checked-in expected output file; the test compares actual
against golden and fails with a diff. Perfect for `symbols` output on a fixture
directory.

**JSON-RPC 2.0 / LSP.** JSON-RPC is a tiny request/response protocol over any
transport. LSP is a JSON-RPC dialect for editors. On stdio, messages are framed
with a `Content-Length:` header followed by a blank line and the JSON body. *Why:*
you will implement the framing by hand, which teaches partial reads — the thing
every socket tutorial gets wrong.

---

## 5. Architecture

```
odin-lens/
  Makefile              build / run / test / release / clean
  .gitignore            binary, *.bin
  GUIDE.md              this file
  src/
    main.odin           package main: CLI parsing, output formatting, exit codes
    lexer/
      token.odin        Token model: Kind enum, Token struct, keyword mapping
      lexer.odin        cursor, scan loop, literals, punctuation table
      lexer_test.odin   @(test) procedures
    index/
      index.odin        Index struct + arenas, directory walk, extraction
      index_test.odin   extraction tests on in-memory source strings
  testdata/
    fixtures/           small .odin files with known declarations
    golden/             expected symbols output
  tools/                Python: differential harness, RPC client
```

**Data flow (batch):** CLI parses args → `index` walks the path → for each `.odin`
file: read bytes into the file arena → `lexer` produces tokens (also file arena) →
heuristic pass copies names into the index arena → file arena reset → sort → format
(text or JSON) → stdout; counters/warnings → stderr.

**Data flow (server):** RPC reads framed JSON → dispatch to the same `index`
functions → serialize the same records. The server must not have a second code
path for answers. If the CLI and the server disagree, that's a design bug.

**Three lifetime rules, memorize them**

1. A token's text is borrowed from the source buffer. The source must outlive the
   token. Tokens are not self-contained.
2. Anything the index keeps (names, paths) must be copied into the index allocator
   *before* the file's scratch memory is reset.
3. Memory allocated from an allocator is freed by that same allocator, and only
   once. Never `delete` something an arena owns; call the arena's free-all.

---

## 6. Contracts (definitions, not code)

You are defining these before implementing them. Changing a contract later is
allowed, but do it deliberately and update tests.

### 6.1 CLI

| Command | Arguments | stdout | stderr | Exit |
|---|---|---|---|---|
| `symbols` | `<file-or-dir>` `[--json]` | declarations (TSV or JSON) | counters, warnings | 0 ok, 1 nothing indexed / unreadable, 2 usage |
| `tokens` | `<file>` | one line per token | lexer errors | 0 ok, 1 unreadable, 2 usage |
| `help`, `-h`, `--help` | — | usage text | — | 0 |

Rules: stdout is for data only (pipeable); diagnostics always go to stderr; exit
codes are meaningful so Python can branch on them.

### 6.2 Symbol record

| Field | Type | Meaning |
|---|---|---|
| `name` | string | declaration name, owned by the index |
| `kind` | enum | one of the kinds below |
| `file` | string | path as given to the indexer, owned by the index |
| `line` | int | 1-based line of the name token |
| `column` | int | 1-based rune column of the name token |

Kinds for v1: `Package`, `Import`, `Procedure`, `Struct`, `Union`, `Enum`,
`Bit_Set`, `Type`, `Constant`, `Variable`.

### 6.3 JSON envelope (`symbols --json`)

```
{
  "root": "<path as given>",
  "file_count": <int>,
  "symbol_count": <int>,
  "symbols": [ <symbol records>, ... ]
}
```

Decision: `kind` is emitted as its **name** (`"Procedure"`), not its numeric value,
so the format survives reordering the enum. The JSON encoder needs an option for
that; find it in `core/encoding/json/marshal.odin` (`use_enum_names`).

### 6.4 RPC methods (M10)

| Method | Params | Result |
|---|---|---|
| `initialize` | `{ "root": string }` | `{ "ok": bool, "version": string }` |
| `index` | `{}` | `{ "file_count": int, "symbol_count": int }` |
| `symbols` | `{}` | array of symbol records |
| `definition` | `{ "name": string }` | first matching symbol or `null` |
| `shutdown` | `{}` | `{}` then exit |

Notifications (no `id`) are accepted and ignored. Unknown methods return a JSON-RPC
error object, never a crash.

---

## 7. Milestones

### M0 — Project skeleton (half a day)

**Goal:** a repository that builds, tests, and commits before there is anything to
build.

**Do**
1. `git init` in `odin-lens`; write `.gitignore` (binary name, `*.bin`).
2. Create `src/` with one file declaring `package main` and a `main` procedure that
   prints usage and exits. Use an explicit output name when building.
3. Write a `Makefile` with `build` (debug build), `run`, `test` (one `odin test`
   per package), `release` (`-o:speed`), `clean`. Add `-vet -vet-unused
   -vet-shadowing` to your dev build.
4. Confirm the fast loop: `odin check src` for type-checking, `odin build` only when
   you need to run.
5. Commit.

**Done when:** `make build && ./<binary>` prints usage; `odin check src` is clean;
one commit exists.

**Traps:** naming the output `something.exe` on Linux (you already did this in
`Webserver/build.sh`); confusing `-out:` (output path) with `-o:` (optimization
level).

---

### M1 — Token model and CLI in miniature (1–2 days)

**Goal:** define the data you will spend the rest of the project producing, and
prove you can do file I/O and error handling.

**Do**
1. Define the token kind enum. Copy the categories from the compiler's own
   `TOKEN_KINDS` macro in `~/Code/Odin/Odin/src/tokenizer.cpp`; use the same names so
   you can navigate the real compiler later.
2. Define the token struct: kind, borrowed text, byte offset, line, column.
3. Implement the `tokens` command far enough to read a file and report its size,
   line count, and the number of bytes read. No lexing yet.
4. Add one test: keyword classification covers the keyword range and excludes
   identifiers (`proc` vs `procedure`, `for` vs `foreach`).

**Learn:** enums as `u8`; struct layout; `string` vs `[]byte`; the read-whole-file
API takes an explicit allocator in this version; `defer` on the file handle;
stderr vs stdout.

**Done when:** the command reads any file you point at, and reports a clean error
(no panic) for a missing path. Tests pass.

**Traps:** a package-level procedure named `make` shadows the builtin `make` inside
that package (verified) — name it `create` or `init`; enum switch exhaustiveness.

**Self-check:** why is the token's text stored as a slice instead of a copy?

---

### M2 — Lexer core (2–3 days)

**Goal:** whitespace, identifiers, keywords, and punctuation, with longest-match.

**Do**
1. Cursor: byte position, current line, current column; operations that advance one
   UTF-8 rune and peek ahead without consuming. Make "always make progress"
   an invariant — an unterminated construct must never loop forever.
2. Skip whitespace; then identifiers (Unicode letters, digits, underscore; cannot
   start with a digit).
3. Map identifier spellings to keyword kinds; everything else stays an identifier.
4. Build a punctuation/operator table ordered **longest first**, and take the first
   match. The authoritative list is the compiler's `TOKEN_KINDS` macro — copy it.
5. `next` returns one token; a `tokenize` convenience collects them into a
   dynamic array and reports the first error.
6. `tokens` command prints line, column, kind, and text (single line per token).

**Done when:** `tokens` on `src/main.odin` produces plausible output; tests cover
keywords vs identifiers and operator longest-match (including `---`, `..=`, `..<`,
`&&=`, `&~=`, `->`, `<<=`).

**Traps:** `1..2` must be integer, range-operator, integer — not a float; `::` and
`:=` are two tokens (Colon Colon / Colon Eq); table order (`<<=` before `<<` before
`<`); `---` vs `--` vs `-`.

**Self-check:** why is a table plus first-match correct, while a hand-written switch
needs care about ordering?

---

### M3 — Literals (2 days)

**Goal:** every literal form a real file contains.

**Do**
1. Numbers: decimal, `0x`, `0b`, `0o`, `_` separators, fractional part, exponent
   with optional sign, imaginary `i` suffix. Fractional part only when the dot is
   followed by a digit.
2. Quoted strings with escapes (`\n`, `\\`, `\"`, `\x41`, `\u00e9`, `\U0001F600`);
   reject raw newlines; unterminated is an error token, not a hang.
3. Raw strings (backticks): no escapes, may contain newlines — and newlines must
   advance the line counter.
4. Rune literals: one rune or one escape, closing quote required.
5. Tests for every form, and for the error paths.

**Learn:** UTF-8 decoding, rune vs byte columns, escape handling as a shared
subroutine, the difference between "invalid token" and "lexer stopped".

**Done when:** all literal tests pass and a token dump of a stdlib file with raw
strings looks right.

**Traps:** `1e9` is a float, but `1e` followed by an identifier is not; Odin does
not accept `.5` as a float; `'\''` (escaped quote) must not terminate the rune
literal early.

---

### M4 — Errors, comments, positions (1 day)

**Goal:** survive real code, and never hang.

**Do**
1. Line comments; block comments **with nesting** (Odin allows `/* a /* b */ c */`).
2. Optional comment retention: a flag on the lexer that returns comment tokens
   instead of skipping. Needed for doc comments later.
3. Error policy: record the first error message on the lexer, emit an invalid
   token, keep going. The command prints the message on stderr and continues.
4. Position tests: 1-based line and column; tabs count as one column; raw-string
   newlines increment the line.

**Done when:** nested-comment test passes; an unterminated string produces exactly
one error and the process exits normally.

**Traps:** nested comments (a non-nesting scanner silently eats the rest of the
file); CRLF; a block comment that never closes must set the error and stop.

**Self-check:** why does a batch indexer prefer "record error and continue" over
"abort the file"?

---

### M5 — Symbol extraction (2–3 days)

**Goal:** turn tokens into symbol records. This is the heart of the project, and it
is deliberately *not* a parser.

**Do**
1. Track brace depth with a counter. Only depth 0 is interesting in v1.
2. Patterns to recognize at depth 0:
   - `package <ident>`
   - `import "<path>"` and `import <alias> "<path>"` (alias wins; otherwise the
     last path segment is the name)
   - `<ident> :: proc` → Procedure; `:: struct`, `:: union`, `:: enum`,
     `:: bit_set` → their kinds
   - `<ident> :: distinct`/`:: map`/`:: [dynamic]`/`:: ^`/`:: ?` → Type
   - `<ident> :: <anything else>` → Constant
   - `<ident> : <Type>` → Variable
3. Copy every kept string into the index allocator. This is not optional: the
   source buffer is scratch.
4. Tests: a fixture covering all kinds; positions; nested declarations ignored
   (declarations inside a procedure body); struct fields not extracted yet;
   names still valid after the source buffer is gone.

**Done when:** `symbols` on a fixture prints exactly the expected lines, and on
`src/` it finds your own declarations.

**Traps:** `::` is two tokens; `foreign import foo "lib"` looks like an import and
that's acceptable, but note it; attributes (`@(private)`, `@(require_results)`)
appear *before* declarations and must not confuse the pattern match; one-line
structs must balance the depth counter; generic procs (`name :: proc($T: ...)`)
still classify as procedures.

**Self-check:** name three inputs where this heuristic is wrong, and say whether
each is acceptable for v1.

---

### M6 — Directory walk and arenas (2 days)

**Goal:** index a tree with bounded memory and no leaks-by-design.

**Do**
1. Two arenas: index (long-lived: symbols, names, paths) and file (scratch: bytes,
   tokens), reset after each file.
2. Walk: open directory, create an iterator, defer its destruction, recurse into
   subdirectories, filter `.odin`, skip hidden directories and symlinks.
3. Build child paths explicitly (don't trust the listing's stored path).
4. Counters: files indexed, symbols found. Print to stderr.
5. Run it on `~/Code/Odin/Odin/core` and watch RSS. It should not grow per file.

**Learn:** allocator lifetimes, iterator protocol, why the returned file entry is
**reused** between iterations (docs in `core/os/dir.odin`) so keeping it requires
a clone, and why a temp allocator reset inside recursion frees your parent's data.

**Done when:** thousands of symbols from `core/`, no panic, flat memory, thousands
of files in under a second or two.

**Traps:** reusing the iterator's file entry across iterations (dangling); resetting
a temp allocator in a recursive call; symlink cycles; a big non-source file being
read into the scratch arena (filter first, then read).

**Self-check:** what breaks if you use one arena for everything?

---

### M7 — Output contract (1 day)

**Goal:** outputs other programs can rely on.

**Do**
1. Text mode: one line per symbol, tab-separated: `file:line:col`, kind, name.
2. JSON mode: the envelope from §6.3, pretty-printed, enum names not numbers.
3. Sort deterministically: file, then line, then name. Directory order is
   filesystem-dependent; tests will flake without this.
4. Exit codes per §6.1.

**Done when:** `symbols --json | python3 -m json.tool` succeeds; two runs on the
same tree produce byte-identical output; empty directory exits 1 with a clear
message.

**Traps:** JSON tags on struct fields (not field names) decide wire names; a running
counter message on stdout breaks the JSON pipe.

---

### M8 — Test suite hardening (2 days)

**Goal:** confidence, not coverage numbers.

**Do**
1. Table-driven tests: one table per concept (literals, operators, comments,
   positions, symbol kinds). Failure messages must name the input.
2. Golden files: a `testdata/fixtures` package and expected output; the test
   compares and prints a diff.
3. Corpus test: tokenize every file under `core/` and assert zero lexer errors. This
   single test is worth more than fifty handwritten cases.
4. Trickle-down coverage: for every token kind, at least one test produces it.

**Done when:** corpus test green on the whole stdlib; golden test stable across
runs; `make test` runs every package's tests.

**Traps:** `odin test` only tests the initial package — wire per-package runs into
the Makefile or you'll have silent untested packages.

---

### M9 — Python differential harness (2 days)

**Goal:** use Python for what it's good at: orchestration and reporting.

**Do**
1. Collect inputs: all stdlib files, plus randomly assembled snippets from a small
   generator (keywords, literals, operators, balanced braces).
2. For each input: run `odin check` (exit code = oracle verdict) and your `tokens`
   command.
3. Assert the differential property: *compiler accepts ⇒ your lexer reports no
   errors.* Report violations with file and line.
4. Second comparison: parse `odin doc <package>` text output (sections:
   `procedures`, `types`, `constants`, `variables`) and compare declaration names
   against your `symbols` output for that package. Expect false positives from
   heuristics; classify them, don't hide them.
5. Make it a pytest suite with a slow marker, and a `--max-failures` report.

**Learn:** subprocess invocation, exit-code semantics, temporary directories,
pytest fixtures, JSON round-trips, the discipline of an oracle.

**Done when:** one command runs the whole differential suite and prints a summary;
violations, if any, are listed as known issues in a file.

**Stretch:** `odin doc -doc-format` emits a binary `.odin-doc` file (verified). Parse
its string table with Python's `struct` for a stronger oracle. Only attempt this
after the text comparison works.

**Traps:** the compiler is slower than your lexer — cache results; don't put
generated files inside your own package directory or you'll index them; distinguish
"compiler failed because of a type error" from "compiler failed because of a syntax
error" (only the latter is a lexing disagreement).

---

### M10 — JSON-RPC server (3–4 days)

**Goal:** the long-lived surface that makes this a tool instead of a script.

**Do**
1. Framing: read `Content-Length` headers until a blank line, then read exactly that
   many bytes. Write the same framing back. Partial reads and writes are the norm —
   loop until done.
2. Dispatch the methods from §6.4 against the same index package. No duplicated
   answer logic.
3. State: index guarded by a mutex (or owned by a single worker goroutine with a
   channel of requests). Start with the mutex; it is simpler to reason about.
4. Background re-index on a thread, triggered by an `index` request. The CLI code
   must already be thread-safe enough to call from another thread (it is, if it has
   no globals).
5. Python client: send `initialize`, `index`, `symbols`; print results. Add a test
   that sends a malformed request and asserts an error object comes back.

**Learn:** `core:thread`, `core:sync` (mutex), channels, protocol framing, the
difference between a request and a notification, why stdout must contain protocol
bytes only.

**Done when:** the Python client round-trips all five methods; a malformed request
yields a JSON-RPC error and the server stays alive; `shutdown` exits 0.

**Traps:** logging to stdout corrupts the protocol; blocking the read loop while
indexing makes the editor feel dead; unbounded response sizes; forgetting to flush.

**Self-check:** why is a channel-based design easier to make correct than shared
state with a mutex, and why did we start with the mutex anyway?

---

### M11 — Performance and increments (optional)

**Goal:** learn to measure before optimizing.

**Do**
1. Measure: files/second, tokens/second, peak RSS, time spent in file I/O vs
   scanning. Record numbers in a file.
2. Then, in order of payoff: (a) stream tokens instead of materializing the whole
   array; (b) replace the linear punctuation scan with a byte dispatch table plus a
   small multi-byte trie; (c) read files in chunks; (d) parallel walking with a
   worker pool and one index mutex; (e) incremental re-index keyed by
   modification time.
3. Re-measure after each change; keep only the wins.

**Done when:** a before/after table exists, and every change is justified by it.

---

## 8. The Python half

Three pieces, in order of value:

1. **Differential harness (M9).** The main event. Python orchestrates the compiler
   and your binary; no FFI, no ABI risk, high signal.
2. **RPC client (M10).** A ~60-line script that frames JSON and prints replies. This
   doubles as your editor integration prototype.
3. **Optional shared-library bridge.** Build the index package as a shared library
   and call it from Python with `ctypes`. This teaches ABI, calling conventions, and
   who frees what. Rules if you do it:
   - expose only C-ABI functions (plain integers and pointers);
   - never return arena pointers to Python — either hand Python a copy, or accept a
     caller-provided buffer and return the required size first;
   - one function to create an index, one to destroy it, one to query, so ownership
     is unambiguous;
   - prove it with a test that calls create → query → destroy a thousand times and
     checks memory does not grow.

Do **not** embed CPython in Odin for v1. It is a large detour with little payoff for
this project.

---

## 9. Test checklist

Keep this as a live checklist; tick items as tests land.

| Area | Cases |
|---|---|
| Empty input | zero-length source yields just EOF |
| Identifiers | ASCII, underscore start, unicode letter, `proc` vs `procedure` |
| Keywords | every keyword kind is reachable; no partial matches |
| Numbers | decimal, `0x`, `0b`, `0o`, underscores, float, exponent, imaginary |
| Ranges | `1..2`, `0..<10`, `..=` |
| Operators | longest match for every multi-char operator; `---` vs `--` |
| Strings | escapes, escaped quote, unterminated, newline rejection |
| Raw strings | multiline, line counter advances, backtick termination |
| Runes | plain, escaped, unicode, malformed |
| Comments | line, block, nested block, unterminated |
| Positions | line/column after multiline tokens; unicode columns |
| Symbols | each kind, import alias, positions, nested ignored, ownership |
| Corpus | whole stdlib: no lexer errors, no panics |

---

## 10. Definition of done for v1

- [ ] `make build && make test` clean from a fresh clone.
- [ ] `symbols` on `~/Code/Odin/Odin/core` exits 0, in under ~2 s, RSS bounded.
- [ ] `--json` output validates and is stable across runs.
- [ ] Corpus test: zero lexer errors on the stdlib.
- [ ] Differential harness green (or violations documented as known issues).
- [ ] RPC client script round-trips all methods.
- [ ] A short `README.md` you would hand to a stranger: what it does, how to run it,
      what it does not do.
- [ ] `git log` reads like a history of decisions, not a dump of code.

---

## 11. Debugging playbook

- **It compiles but output is wrong.** Add a `tokens` dump for the smallest failing
  file. Fix the lexer before touching the indexer. Most "symbol bugs" are token bugs.
- **Panic on slicing.** A slice offset is outside the source. Print `offset`, `len`,
  and the source length at the failure site; a byte/rune column mix-up or an
  `advance` that ran past the end is the usual cause.
- **Garbage names in output.** You kept a borrowed slice. Copy it into the index
  arena at the point of creation.
- **Memory grows while indexing.** The scratch arena is not being reset, or you are
  keeping the directory iterator's reused entry.
- **Test flakes.** Unsorted filesystem order. Sort before comparing.
- **Compiler accepts, your lexer errors.** Reproduce with `tokens` on that file, then
  read the corresponding branch in `~/Code/Odin/Odin/src/tokenizer.cpp`.

---

## 12. Reference map

| Need | Where to look |
|---|---|
| Token kinds, operator spellings | `Odin/src/tokenizer.cpp`, `TOKEN_KINDS` macro |
| How tokens are actually scanned | same file, `tokenizer_get_token` |
| Directory iteration semantics | `core/os/dir.odin` |
| Arena API | `core/mem/allocators.odin` |
| JSON tags and options | `core/encoding/json/marshal.odin` |
| Test macros | `core/testing/testing.odin` |
| Real Odin code in volume | `core/`, `vendor/` in the repo you cloned |
| Language overview | `odin-lang.org/docs` |

Commands you'll type daily:

```
odin check src                      # type-check, fast
odin build src -debug -out:out/debug/odin-lens -vet -vet-unused -vet-shadowing
odin test src/lexer                 # per package, remember
odin doc <dir>                      # the oracle for declarations
odin doc <dir> -doc-format -out:tmp # binary doc dump (stretch oracle)
odin report                         # environment info if something is broken
```
