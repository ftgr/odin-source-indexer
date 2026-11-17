package main

import "core:bytes"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

// read_source reads the whole file at path into a buffer allocated with
// allocator. The caller owns data on success and frees it with
// delete(data, allocator). size is the length the OS reports for the file and
// equals len(data) when the whole read succeeds.
read_source :: proc(
	path: string,
	allocator: mem.Allocator,
) -> (
	data: []byte,
	size: i64,
	err: os.Error,
) {
	// 1. Open for reading.
	f, open_err := os.open(path, os.O_RDONLY)
	if open_err != nil {
		return nil, 0, open_err
	}

	// 2. Always close the handle. A close failure after a successful read must
	//    not leak the buffer, so free it here and still report an error.
	defer {
		if close_err := os.close(f); close_err != nil && err == nil {
			delete(data, allocator)
			data = nil
			size = 0
			err = close_err
		}
	}

	// 3. Ask the OS for the exact byte length.
	size, err = os.file_size(f)
	if err != nil {
		return nil, 0, err
	}
	// A negative size, or one that cannot be represented as int, is not a file
	// we can allocate for.
	if size < 0 || i64(int(size)) != size {
		return nil, 0, os.General_Error.Invalid_File
	}

	// 4. Allocate exactly that many bytes on the caller's allocator.
	buffer, alloc_err := make([]byte, int(size), allocator)
	if alloc_err != nil {
		return nil, 0, alloc_err
	}

	// 5. Read until the buffer is full; free it if the read fails.
	ok := false
	defer if !ok {
		delete(buffer, allocator)
	}

	bytes_read, read_err := os.read_full(f, buffer)
	if read_err != nil {
		return nil, 0, read_err
	}

	ok = true
	return buffer[:bytes_read], size, nil
}

// count_lines counts newline-terminated lines: an empty buffer has 0 lines,
// "a" has 1, "a\n" has 1 (no phantom line after the trailing newline), and
// "a\n\n" has 2. '\r' is not a newline here; CRLF files are handled in M4.
count_lines :: proc(data: []byte) -> int {
	if len(data) == 0 {
		return 0
	}

	newlines := bytes.count(data, []byte{'\n'})
	if data[len(data) - 1] != '\n' {
		return newlines + 1
	}
	return newlines
}

// run_tokens implements `tokens <file>`: read the file and report its path,
// size, line count, and the number of bytes read. Exit codes: 0 success,
// 1 I/O error, 2 usage error.
run_tokens :: proc(command: []string, allocator: mem.Allocator) -> int {
	// 1. Validate CLI arity: expects e.g. ["prog", "tokens", "<filepath>"].
	if len(command) != 3 {
		prog := len(command) > 0 ? command[0] : "odin-source-indexer"
		fmt.eprintfln("usage: %s tokens <file>", prog)
		return 2
	}

	filepath := command[2]

	// 2. Read the source file using the caller-supplied allocator.
	data, size, err := read_source(filepath, allocator)
	if err != nil {
		log.errorf("tokens: %s: %v", filepath, err)
		return 1
	}
	// Placed strictly after the error check so we never free a failed read.
	defer delete(data, allocator)

	// 3. Compute the summary and emit data to stdout only.
	lines := count_lines(data)
	fmt.printfln("path:  %s", filepath)
	fmt.printfln("size:  %d bytes", size)
	fmt.printfln("lines: %d", lines)
	fmt.printfln("read:  %d bytes", len(data))

	return 0
}
