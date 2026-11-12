package main

import "core:fmt"
import "core:os"

usage :: proc(out: ^os.File) {
	fmt.fprintln(out, "symbols <file-or-dir> [--json]")
	fmt.fprintln(out, "tokens <file>")
	fmt.fprintln(out, "help, -h, --help")
}

// Returns 0 on success and 1 for an unknown command. Diagnostics go to stderr;
// only real output is written to stdout (see GUIDE.md section 6.1).
validate_command :: proc(command: []string) -> int {
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
		fmt.println("tokens...")
		return 0
	}

	fmt.eprintln("Not a valid command!")
	usage(os.stderr)
	return 1
}
