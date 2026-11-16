# odin-source-indexer — build, check, test, verify
#
# Strict by default: warnings are errors, style is enforced, unused things fail
# the build. If a check is too noisy while you are experimenting, run the plain
# `odin` command directly instead of weakening this file.

ODIN    ?= odin
ODINFMT ?= odinfmt

OUT         := out
BIN_NAME    := odin-source-indexer
DEBUG_BIN   := $(OUT)/debug/$(BIN_NAME)
RELEASE_BIN := $(OUT)/release/$(BIN_NAME)
SRC         := src
FMT_CFG     := odinfmt.json

# Every directory under src/ that holds .odin files, for per-package `odin test`
# and `odin check`. (odin test only runs @(test) procedures in the initial
# package.)
PKGS     := $(shell find $(SRC) -name '*.odin' -exec dirname {} \; 2>/dev/null | sort -u)
LIB_PKGS := $(filter-out $(SRC),$(PKGS))

# --- flags ------------------------------------------------------------------

# Diagnostics: unused variables/imports, shadowing, implicit casts, stray
# semicolons, tabs. These catch the mistakes that cost you an evening.
VET := -vet -vet-unused -vet-unused-variables -vet-unused-imports \
       -vet-shadowing -vet-cast -vet-semicolon -vet-tabs -vet-style

# Language/style law. -error-pos-style:unix emits file:line:col so editors,
# grep, and scripts can jump straight to the error.
STYLE := -strict-style -disallow-do -warnings-as-errors -error-pos-style:unix

DEV     := -debug $(VET) $(STYLE)
RELEASE := -o:speed $(VET) $(STYLE)

# Tests fail on leaked memory instead of merely reporting it. Values must be
# `true`/`false` here: `1` is a string, and a `when` on a non-constant bool is a
# compile error in core:testing.
TEST_DEFINES := -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
                -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true

# --- targets ----------------------------------------------------------------

.PHONY: all build release run run-release check test fmt fmt-check verify clean install-hooks

# Artefacts are split by configuration so debug builds never clobber a release
# binary. Order-only prerequisites: create the directory if missing, but never
# rebuild just because the directory's timestamp changed.
$(OUT)/debug:
	mkdir -p $@

$(OUT)/release:
	mkdir -p $@

all: build

# Debug build: symbols, bounds checks, strict diagnostics.
build: | $(OUT)/debug
	$(ODIN) build $(SRC) -out:$(DEBUG_BIN) $(DEV)

# Optimised build. Still strict, because shipping sloppy code is not a reward.
release: | $(OUT)/release
	$(ODIN) build $(SRC) -out:$(RELEASE_BIN) $(RELEASE)

run: build
	./$(DEBUG_BIN)

run-release: release
	./$(RELEASE_BIN)

# Type-check only: the fast inner loop. No binary is produced. `odin check src`
# covers the initial package only, so library packages are checked separately
# with -no-entry-point.
check:
	$(ODIN) check $(SRC) $(VET) $(STYLE)
	@set -e; \
	for pkg in $(LIB_PKGS); do \
		printf '\n== %s\n' "$$pkg"; \
		$(ODIN) check "$$pkg" -no-entry-point $(VET) $(STYLE); \
	done

# One `odin test` invocation per package, or nested packages go untested.
test:
	@set -e; \
	for pkg in $(PKGS); do \
		printf '\n== %s\n' "$$pkg"; \
		$(ODIN) test "$$pkg" $(DEV) $(TEST_DEFINES); \
	done

# Rewrite sources in place. Run before committing.
fmt:
	$(ODINFMT) -path:$(SRC) -w -config:$(FMT_CFG)

# Fail if anything is not formatted. odinfmt has no --check, so compare output.
fmt-check:
	@./tools/fmt-check.sh

# The gate the pre-commit hook runs.
verify: fmt-check check test
	@echo "verify: all checks passed"

clean:
	rm -rf $(OUT)
	rm -rf .cache

# Point git at the versioned hooks in .githooks/.
install-hooks:
	git config core.hooksPath .githooks
	@echo "hooks installed: $$(git config core.hooksPath)"
