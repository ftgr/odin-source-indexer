package index

import "../lexer"
import "core:mem"
import "core:os"
import "core:strings"

// Index_Error is any failure from the batch index: filesystem, allocation,
// lexical, or a walk-specific problem.
Index_Error :: union {
	os.Error,
	mem.Allocator_Error,
	lexer.Lex_Error,
	Walk_Error,
}

// Walk_Error names problems the batch walker detects itself.
Walk_Error :: enum u8 {
	Path_Too_Long,
}

// Walk_Error_Proc receives every recoverable problem. path is borrowed for the
// duration of the call; line and column are zero when they do not apply. The
// index package never prints: the CLI supplies a callback that logs.
Walk_Error_Proc :: #type proc(user_data: rawptr, path: string, line, column: int, err: Index_Error)

Walk_Options :: struct {
	on_error:  Walk_Error_Proc,
	user_data: rawptr,
}

// Walk_Stats counts one index_path call.
Walk_Stats :: struct {
	files:    int, // files read and tokenized successfully
	symbols:  int, // symbols appended to the Index
	failures: int, // files or directory entries that could not be indexed
}

// 4096 is the usual PATH_MAX on Linux. Paths longer than this are reported as
// Walk_Error.Path_Too_Long instead of truncating.
PATH_BUFFER_SIZE :: 4096

// index_path indexes a single file or recursively walks a directory. Root
// errors are returned; per-file and per-entry errors go to options.on_error and
// increment stats.failures so the rest of the tree is still indexed.
index_path :: proc(
	path: string,
	idx: ^Index,
	arenas: ^Index_Arenas,
	options := Walk_Options{},
) -> (
	stats: Walk_Stats,
	err: Index_Error,
) {
	if os.is_dir(path) {
		return walk_directory(path, idx, arenas, options)
	}

	added, file_err := index_file(path, idx, arenas, options)
	if file_err != nil {
		stats.failures = 1
		return stats, file_err
	}
	stats.files = 1
	stats.symbols = added
	return
}

// index_file reads and indexes one source file. All bytes and tokens live in
// the file arena, which is reset when the procedure returns; retained names and
// paths are cloned into the index arena by extract_file.
index_file :: proc(
	path: string,
	idx: ^Index,
	arenas: ^Index_Arenas,
	options: Walk_Options,
) -> (
	added: int,
	err: Index_Error,
) {
	defer index_arenas_reset_file(arenas)

	file_allocator := index_arenas_file_allocator(arenas)
	data, read_err := os.read_entire_file_from_path(path, file_allocator)
	if read_err != nil {
		return 0, read_err
	}

	lex := lexer.lexer_init(string(data))
	tokens, tokenize_err := lexer.tokenize(&lex, file_allocator)
	if tokenize_err != nil {
		return 0, tokenize_err
	}

	// Lexical problems do not stop extraction: they become Invalid tokens and
	// the first one is reported as a warning for this file.
	if lex.error != .None {
		report_walk_error(options, path, lex.error_line, lex.error_column, lex.error)
	}

	before := len(idx.symbols)
	extract_err := extract_file(tokens, path, idx, index_arenas_index_allocator(arenas))
	if extract_err != nil {
		return 0, extract_err
	}
	return len(idx.symbols) - before, nil
}

// walk_directory recursively indexes the .odin files under path. It never
// follows symbolic links, skips hidden entries, and builds child paths on the
// stack so resetting the file arena inside a child cannot free an ancestor path.
walk_directory :: proc(
	path: string,
	idx: ^Index,
	arenas: ^Index_Arenas,
	options: Walk_Options,
) -> (
	stats: Walk_Stats,
	err: Index_Error,
) {
	f, open_err := os.open(path, os.O_RDONLY)
	if open_err != nil {
		return stats, open_err
	}
	defer {
		if close_err := os.close(f); close_err != nil && err == nil {
			err = close_err
		}
	}

	it := os.read_directory_iterator_create(f)
	defer os.read_directory_iterator_destroy(&it)

	iter_failed := false
	for fi in os.read_directory_iterator(&it) {
		if err_path, iter_err := os.read_directory_iterator_error(&it); iter_err != nil {
			iter_failed = true
			stats.failures += 1
			report_walk_error(options, err_path, 0, 0, iter_err)
			continue
		}

		// Hidden entries include "." and ".."; symlinks are skipped so the
		// walk cannot cycle and never indexes a file twice through a link.
		if len(fi.name) == 0 || fi.name[0] == '.' || fi.type == .Symlink {
			continue
		}

		child_buf: [PATH_BUFFER_SIZE]u8
		child, child_ok := join_child_path(path, fi.name, child_buf[:])
		if !child_ok {
			stats.failures += 1
			report_walk_error(options, path, 0, 0, Walk_Error.Path_Too_Long)
			continue
		}

		#partial switch fi.type {
		case .Directory:
			sub, sub_err := walk_directory(child, idx, arenas, options)
			stats.files += sub.files
			stats.symbols += sub.symbols
			stats.failures += sub.failures
			if sub_err != nil {
				stats.failures += 1
				report_walk_error(options, child, 0, 0, sub_err)
			}
		case .Regular:
			// Filter before reading: a large non-source file must never enter
			// the file arena.
			if !strings.has_suffix(fi.name, ".odin") {
				continue
			}

			added, file_err := index_file(child, idx, arenas, options)
			if file_err != nil {
				stats.failures += 1
				report_walk_error(options, child, 0, 0, file_err)
			} else {
				stats.files += 1
				stats.symbols += added
			}
		}
	}

	if !iter_failed {
		if _, iter_err := os.read_directory_iterator_error(&it); iter_err != nil {
			return stats, iter_err
		}
	}
	return
}

// join_child_path joins a directory and a child name into buf, adding one path
// separator only when the parent does not already end with one. It returns
// ok=false when the result does not fit.
join_child_path :: proc(parent, name: string, buf: []byte) -> (path: string, ok: bool) {
	separator := os.Path_Separator_String
	need := len(parent) + len(name)
	if len(parent) == 0 || parent[len(parent) - 1] != separator[0] {
		need += len(separator)
	}
	if need > len(buf) {
		return "", false
	}

	n := copy(buf, parent)
	if len(parent) == 0 || parent[len(parent) - 1] != separator[0] {
		n += copy(buf[n:], separator)
	}
	n += copy(buf[n:], name)
	return string(buf[:n]), true
}

// report_walk_error forwards a recoverable error when the caller supplied a
// callback.
report_walk_error :: proc(
	options: Walk_Options,
	path: string,
	line, column: int,
	err: Index_Error,
) {
	if options.on_error != nil {
		options.on_error(options.user_data, path, line, column, err)
	}
}
