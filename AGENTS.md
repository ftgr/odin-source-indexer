# odin-source-indexer — agent instructions

Project conventions on top of `GUIDE.md`. Follow them unless a milestone says
otherwise; if a rule has to be broken, leave a comment explaining why.

## Logging: `core:log`, to stderr, never stdout

- Use `core:log` (`log.debug/info/warn/error`, `log.errorf`) for diagnostics,
  progress, and errors. Do not add `fmt.println`/`fmt.eprintln` for those.
- `fmt` is only for command output: usage text, `symbols`/`tokens` data, and
  `--json`.
- **stdout is data only** (GUIDE §6.1). The default console logger sends
  Debug/Info/Warn to stdout, so point the logger at stderr explicitly:

  ```odin
  context.logger = log.create_file_logger(os.stderr)
  defer log.destroy_file_logger(context.logger)
  ```

- Levels: `debug` internals, `info` normal progress, `warn` recovered
  oddities, `error`/`errorf` failures. No `log.fatal` outside `main`, and never
  for invalid user input.
- Tests own their logger (`core:testing`); assert with `testing.expect*`
  instead of printing.

## Memory: every allocating procedure takes an allocator

- If a procedure allocates — `make`, `new`, `append`, `strings.clone`,
  `fmt.aprintf`, or any stdlib call that takes an allocator — it takes
  `allocator: mem.Allocator` as its final parameter and threads that allocator
  through every allocation in its body.
- Do not read `context.allocator` inside such procedures. Only the outermost
  CLI entry point may default it (prefer passing the allocator down instead).
- A procedure that returns allocated data returns ownership: document which
  allocator owns the result and that the caller frees it with the same one.
- Free with the allocator that produced the memory: `delete(x, allocator)` /
  `free(ptr, allocator)`, not the default `delete(x)` on foreign data.
- Allocation builtins are `#optional_allocator_error`: the single-value form
  (`x := make(...)`) silently yields nil/empty on failure. Take the error and
  handle it (see the errors section).
- Check leaks in debug builds with `mem.Tracking_Allocator`. Pass it in
  instead of overwriting `context.allocator` — that keeps logger and `defer`
  ordering honest:

  ```odin
  run :: proc(allocator: mem.Allocator) -> int { /* work */ }

  cli :: proc() -> int {
  	exit_code := 0

  	when ODIN_DEBUG {
  		track: mem.Tracking_Allocator
  		mem.tracking_allocator_init(&track, context.allocator)
  		defer mem.tracking_allocator_destroy(&track)

  		exit_code = run(mem.tracking_allocator(&track))

  		for _, leak in track.allocation_map {
  			log.errorf("%v leaked %m", leak.location, leak.size)
  		}
  	} else {
  		exit_code = run(context.allocator)
  	}

  	return exit_code
  }
  ```

- Do not call `os.exit` while a `defer` is pending — Odin rejects that as an
  unreachable defer. Return to `main` and exit there.
- `mem` must stay referenced outside `when ODIN_DEBUG` (the allocator
  parameter above does it), or release builds fail `-vet-unused-imports`.
- Apply tracking at ownership boundaries (CLI entry, index), not per-token or
  `context.temp_allocator` scratch paths — the tracking map would dwarf the
  allocations and hide real leaks.
- Test binaries already track memory: the Makefile sets
  `ODIN_TEST_FAIL_ON_BAD_MEMORY` and `ODIN_TEST_ALWAYS_REPORT_MEMORY`. Fix the
  leak; never weaken those defines.

## Errors: handle everything that can fail

Odin has no exceptions. A fallible call returns its failure in a second value
(`ok`, `os.Error`, `mem.Allocator_Error`, ...); that value is part of the
contract.

- **Return the error last.** A fallible procedure returns `(value, err)` or
  `(a, b, err)` — never `(err, value)`. `or_return` propagates the final value
  into the caller's error slot, and `or_else`/`value, ok` idioms read the same
  trailing position. This matches `core:os`, `core:mem`, and every
  standard-library fallible call.

  ```odin
  // Correct: the error is the last return value.
  load :: proc(path: string, allocator: mem.Allocator) -> (data: []byte, err: os.Error)

  // Wrong: or_return cannot see this error.
  load_bad :: proc(path: string) -> (err: os.Error, data: []byte)
  ```

- Never discard a result that can fail: no `_ = err`, no single-value form of a
  two-result call, no `assert(err == nil)` on data that comes from the user or
  the filesystem.
- Propagate with `or_return` when the enclosing signature returns a compatible
  error type; translate explicitly when it does not. The two rules compose —
  allocator in, error out:

  ```odin
  load :: proc(path: string, allocator: mem.Allocator) -> (data: []byte, err: os.Error) {
  	data = os.read_entire_file(path, allocator) or_return
  	return
  }
  ```
- Use `or_else` only for a documented, correct fallback; use `or_break` /
  `or_continue` inside loops.
- Map lookups are fallible: use `v, ok := m[k]` and branch on `ok`; a zero value
  is not evidence that the key was found.
- `assert` is for invariants and compiler bugs. Missing files, unreadable
  paths, malformed source, and bad CLI input are expected errors: report them
  with `log.error`/`log.errorf` and a nonzero exit code.
- Acquire, then `defer` cleanup immediately (`defer close(f)`,
  `defer delete(buf, allocator)`); every success path and every early return
  must release the same resources.
- Library code returns errors; only the CLI boundary prints diagnostics and
  exits (GUIDE §6.1). Never `os.exit` from a lexer/index helper.
- Tests: fail on unexpected errors and include the error value in the message
  (`testing.expect(t, err == nil, ...)` then the real assertion; `testing.fail`
  for precondition failures).

## Build and verification

- `make check` is the fast loop; `make verify` is the pre-commit gate
  (fmt-check + check + per-package tests). Both must pass before committing.
- Builds are strict: warnings are errors, unused imports/variables fail, tabs
  only. Do not add `_ :: x` or similar silencers to get green.
- Format with `make fmt` (repo `odinfmt.json`: 100 columns, tabs, sorted
  imports); never use a different formatter config.
