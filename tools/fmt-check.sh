#!/usr/bin/env bash
#
# Fail if any .odin file is not formatted.
#
# odinfmt has no --check mode, so the only way to detect drift is to format to
# stdout and diff it against the file on disk.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ODINFMT="${ODINFMT:-odinfmt}"
CONFIG="odinfmt.json"

if ! command -v "$ODINFMT" >/dev/null 2>&1; then
	echo "fmt-check: $ODINFMT not found in PATH" >&2
	exit 1
fi

if [[ ! -f $CONFIG ]]; then
	echo "fmt-check: $CONFIG not found" >&2
	exit 1
fi

status=0
count=0

while IFS= read -r -d '' file; do
	count=$((count + 1))
	if ! formatted="$("$ODINFMT" -path:"$file" -config:"$CONFIG" 2>&1)"; then
		printf 'fmt-check: %s: formatter failed\n' "$file" >&2
		printf '%s\n' "$formatted" | head -5 >&2
		status=1
		continue
	fi
	if ! diff -q <(printf '%s\n' "$formatted") "$file" >/dev/null; then
		printf 'fmt-check: %s is not formatted (run: make fmt)\n' "$file" >&2
		diff -u "$file" <(printf '%s\n' "$formatted") | head -40 >&2
		status=1
	fi
done < <(find . -name '*.odin' -not -path './vendor/*' -print0)

if [[ $status -eq 0 ]]; then
	printf 'fmt-check: %d file(s) formatted\n' "$count"
fi

exit $status
