package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

usage :: proc(out: ^os.File) {
	fmt.fprintln(out, "symbols <file-or-dir> [--json]")
	fmt.fprintln(out, "tokens <file>")
	fmt.fprintln(out, "help, -h, --help")
}

// Returns an exit code: 0 on success, 1 for an I/O error, 2 for a usage error
// (unknown command or bad arguments). Diagnostics go to stderr; only real
// output is written to stdout (see GUIDE.md section 6.1).
validate_command :: proc(command: []string, allocator: mem.Allocator) -> int {
	if len(command) < 2 {
		usage(os.stdout)
		return 0
	}

	switch command[1] {
	case "help", "-h", "--help":
		usage(os.stdout)
		return 0
	case "symbols":
		fmt.println("symbols...")
		return 0
	case "tokens":
		return run_tokens(command, allocator)
	}

	log.errorf("unknown command: %s", command[1])
	usage(os.stderr)
	return 2
}
