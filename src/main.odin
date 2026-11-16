package main

import "core:log"
import "core:mem"
import "core:os"

// M1 CLI boundary: logging, leak tracking, and dispatch. Keeping this out of
// main lets the defers run before os.exit (Odin rejects os.exit while a defer
// is pending).
main :: proc() {
	os.exit(cli())
}

cli :: proc() -> int {
	context.logger = log.create_file_logger(os.stderr)
	defer log.destroy_file_logger(context.logger)

	exit_code: int

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

run :: proc(allocator: mem.Allocator) -> int {
	return validate_command(os.args, allocator)
}
