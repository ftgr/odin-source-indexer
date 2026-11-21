package main

import "core:bytes"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "index"
import "lexer"

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
// "a\n\n" has 2. Only '\n' terminates a line, so each "\r\n" counts once and a
// lone '\r' is not a line break.
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

// run_tokens implements `tokens <file>`: read the file and dump its token
// stream as `line:column kind text`, one token per line. Exit codes follow
// GUIDE 6.1: 0 when the file was read and tokenized (even if the lexer recorded
// a lexical error), 1 when the file cannot be read, 2 for a usage error.
run_tokens :: proc(command: []string, allocator: mem.Allocator) -> int {
	// 1. Validate CLI arity: expects e.g. ["prog", "tokens", "<filepath>"].
	if len(command) != 3 {
		prog := len(command) > 0 ? command[0] : "odin-source-indexer"
		fmt.eprintfln("usage: %s tokens <file>", prog)
		return 2
	}

	filepath := command[2]

	// 2. Read the source file using the caller-supplied allocator.
	data, _, err := read_source(filepath, allocator)
	if err != nil {
		log.errorf("tokens: %s: %v", filepath, err)
		return 1
	}
	// Placed strictly after the error check so we never free a failed read.
	defer delete(data, allocator)

	// 3. Tokenize. string(data) is a view, not a copy, so every Token.text
	//    borrows this buffer and stays valid until the deferred delete.
	lex := lexer.lexer_init(string(data))
	tokens, tokenize_err := lexer.tokenize(&lex, allocator)
	if tokenize_err != nil {
		log.errorf("tokens: %s: %v", filepath, tokenize_err)
		return 1
	}
	defer delete(tokens, allocator)

	// 4. Emit data to stdout only.
	for tok in tokens {
		fmt.printf("%d:%d\t%v\t%q\n", tok.line, tok.column, tok.kind, tok.text)
	}

	// 5. Lexical problems do not stop the scan: the invalid token is already in
	//    the stream, so report the first one on stderr and still succeed. The
	//    token dump is complete; GUIDE 6.1 reserves exit 1 for unreadable input.
	if lex.error != .None {
		log.errorf("tokens: %s:%d:%d: %v", filepath, lex.error_line, lex.error_column, lex.error)
	}

	return 0
}

// run_symbols implements `symbols <file>`: read the file, extract its top-level
// declarations, and print one line per symbol as
// `file:line:column<TAB>kind<TAB>name`. Exit codes: 0 when at least one symbol
// was found, 1 for an unreadable file, an allocation failure, or an empty index,
// 2 for a usage error.
run_symbols :: proc(command: []string, allocator: mem.Allocator) -> int {
	if len(command) != 3 {
		prog := len(command) > 0 ? command[0] : "odin-source-indexer"
		fmt.eprintfln("usage: %s symbols <file>", prog)
		return 2
	}
	filepath := command[2]

	data, _, err := read_source(filepath, allocator)
	if err != nil {
		log.errorf("symbols: %s: %v", filepath, err)
		return 1
	}
	defer delete(data, allocator)

	lex := lexer.lexer_init(string(data))
	tokens, tokenize_err := lexer.tokenize(&lex, allocator)
	if tokenize_err != nil {
		log.errorf("symbols: %s: %v", filepath, tokenize_err)
		return 1
	}
	defer delete(tokens, allocator)

	// A lexical error leaves an Invalid token but does not stop the scan, so
	// report it once and keep the symbols that were found.
	if lex.error != .None {
		log.errorf("symbols: %s:%d:%d: %v", filepath, lex.error_line, lex.error_column, lex.error)
	}

	idx, index_err := index.index_init(allocator)
	if index_err != nil {
		log.errorf("symbols: %s: %v", filepath, index_err)
		return 1
	}
	defer index.index_destroy(&idx, allocator)

	if extract_err := index.extract_file(tokens, filepath, &idx, allocator); extract_err != nil {
		log.errorf("symbols: %s: %v", filepath, extract_err)
		return 1
	}

	for sym in idx.symbols {
		fmt.printf("%s:%d:%d\t%v\t%s\n", sym.file, sym.line, sym.column, sym.kind, sym.name)
	}

	if len(idx.symbols) == 0 {
		log.errorf("symbols: %s: no declarations found", filepath)
		return 1
	}
	return 0
}
