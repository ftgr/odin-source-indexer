package index

import "core:os"
import "core:testing"

// make_test_tree creates a fresh directory under the system temp directory.
// The caller owns root and must call os.remove_all(root) and delete(root).
make_test_tree :: proc(t: ^testing.T, name: string) -> (root: string, ok: bool) {
	temp, temp_err := os.temp_directory(context.allocator)
	if !testing.expectf(t, temp_err == nil, "temp_directory: %v", temp_err) {
		return "", false
	}
	defer delete(temp, context.allocator)

	joined, join_err := os.join_path({temp, name}, context.allocator)
	if !testing.expectf(t, join_err == nil, "join_path: %v", join_err) {
		return "", false
	}

	_ = os.remove_all(joined) // clean up after an interrupted previous run
	if make_err := os.make_directory_all(joined); make_err != nil {
		testing.expectf(t, false, "make_directory_all(%s): %v", joined, make_err)
		delete(joined, context.allocator)
		return "", false
	}
	return joined, true
}

// write_tree_file creates rel under root, including parent directories.
write_tree_file :: proc(t: ^testing.T, root, rel, content: string) -> bool {
	path, join_err := os.join_path({root, rel}, context.allocator)
	if !testing.expectf(t, join_err == nil, "join_path(%s): %v", rel, join_err) {
		return false
	}
	defer delete(path, context.allocator)

	parent, _ := os.split_path(path)
	if parent != "" {
		if make_err := os.make_directory_all(parent); make_err != nil && make_err != .Exist {
			return testing.expectf(t, false, "make_directory_all(%s): %v", parent, make_err)
		}
	}
	if write_err := os.write_entire_file_from_string(path, content); write_err != nil {
		return testing.expectf(t, false, "write %s: %v", path, write_err)
	}
	return true
}

has_symbol :: proc(idx: ^Index, kind: Symbol_Kind, name: string) -> bool {
	for sym in idx.symbols {
		if sym.kind == kind && sym.name == name {
			return true
		}
	}
	return false
}

@(test)
walk_tree_test :: proc(t: ^testing.T) {
	root, ok := make_test_tree(t, "odin-lens-m6-tree")
	if !ok {
		return
	}
	defer delete(root, context.allocator)
	defer os.remove_all(root)

	if !write_tree_file(t, root, "a.odin", "package a\n\nA :: struct {}\n") ||
	   !write_tree_file(t, root, "b.odin", "package a\n\nB :: proc() {}\n") ||
	   !write_tree_file(t, root, "ignore.txt", "package ignored\n\nIgnored :: 1\n") ||
	   !write_tree_file(t, root, ".dot.odin", "package dot\n\nDot :: 1\n") ||
	   !write_tree_file(t, root, ".hidden/skip.odin", "package hidden\n\nHidden :: 1\n") ||
	   !write_tree_file(t, root, "sub/c.odin", "package sub\n\nC :: enum { One }\n") ||
	   !write_tree_file(t, root, "sub/deep/d.odin", "package deep\n\nD :: 1\n") {
		return
	}

	// A symlink to a source file and a symlink cycle must both be skipped.
	link_path, link_err := os.join_path({root, "link.odin"}, context.allocator)
	if !testing.expectf(t, link_err == nil, "join_path(link.odin): %v", link_err) {
		return
	}
	defer delete(link_path, context.allocator)
	if symlink_err := os.symlink("a.odin", link_path); symlink_err != nil {
		testing.expectf(t, false, "symlink(link.odin): %v", symlink_err)
		return
	}

	loop_path, loop_err := os.join_path({root, "loop"}, context.allocator)
	if !testing.expectf(t, loop_err == nil, "join_path(loop): %v", loop_err) {
		return
	}
	defer delete(loop_path, context.allocator)
	if symlink_err := os.symlink(".", loop_path); symlink_err != nil {
		testing.expectf(t, false, "symlink(loop): %v", symlink_err)
		return
	}

	arenas: Index_Arenas
	index_arenas_init(&arenas, context.allocator)
	defer index_arenas_destroy(&arenas)

	idx, init_err := index_init(index_arenas_index_allocator(&arenas))
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return
	}
	defer index_destroy(&idx, index_arenas_index_allocator(&arenas))

	stats, walk_err := index_path(root, &idx, &arenas)
	if !testing.expectf(t, walk_err == nil, "index_path(%s): %v", root, walk_err) {
		return
	}

	testing.expect_value(t, stats.files, 4)
	testing.expect_value(t, stats.symbols, 8)
	testing.expect_value(t, stats.failures, 0)
	testing.expect_value(t, len(idx.symbols), 8)

	// Names from every tree depth survive the per-file arena resets.
	testing.expect(t, has_symbol(&idx, .Struct, "A"), "A should be indexed")
	testing.expect(t, has_symbol(&idx, .Procedure, "B"), "B should be indexed")
	testing.expect(t, has_symbol(&idx, .Enum, "C"), "C should be indexed")
	testing.expect(t, has_symbol(&idx, .Constant, "D"), "D should be indexed")

	// Hidden entries, non-.odin files, and symlinks must not leak into the index.
	testing.expect(t, !has_symbol(&idx, .Constant, "Ignored"), "ignore.txt must be skipped")
	testing.expect(t, !has_symbol(&idx, .Constant, "Dot"), ".dot.odin must be skipped")
	testing.expect(t, !has_symbol(&idx, .Constant, "Hidden"), ".hidden must be skipped")
}

@(test)
walk_single_file_test :: proc(t: ^testing.T) {
	root, ok := make_test_tree(t, "odin-lens-m6-file")
	if !ok {
		return
	}
	defer delete(root, context.allocator)
	defer os.remove_all(root)

	if !write_tree_file(t, root, "only.odin", "package only\n\nOnly :: struct {}\n") {
		return
	}

	file_path, join_err := os.join_path({root, "only.odin"}, context.allocator)
	if !testing.expectf(t, join_err == nil, "join_path(only.odin): %v", join_err) {
		return
	}
	defer delete(file_path, context.allocator)

	arenas: Index_Arenas
	index_arenas_init(&arenas, context.allocator)
	defer index_arenas_destroy(&arenas)

	idx, init_err := index_init(index_arenas_index_allocator(&arenas))
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return
	}
	defer index_destroy(&idx, index_arenas_index_allocator(&arenas))

	stats, walk_err := index_path(file_path, &idx, &arenas)
	if !testing.expectf(t, walk_err == nil, "index_path(%s): %v", file_path, walk_err) {
		return
	}
	testing.expect_value(t, stats.files, 1)
	testing.expect_value(t, stats.symbols, 2)
	testing.expect(t, has_symbol(&idx, .Struct, "Only"), "Only should be indexed")
}

@(test)
walk_empty_directory_test :: proc(t: ^testing.T) {
	root, ok := make_test_tree(t, "odin-lens-m6-empty")
	if !ok {
		return
	}
	defer delete(root, context.allocator)
	defer os.remove_all(root)

	arenas: Index_Arenas
	index_arenas_init(&arenas, context.allocator)
	defer index_arenas_destroy(&arenas)

	idx, init_err := index_init(index_arenas_index_allocator(&arenas))
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return
	}
	defer index_destroy(&idx, index_arenas_index_allocator(&arenas))

	stats, walk_err := index_path(root, &idx, &arenas)
	testing.expect(t, walk_err == nil, "an empty directory should not fail")
	testing.expect_value(t, stats.files, 0)
	testing.expect_value(t, stats.symbols, 0)
	testing.expect_value(t, stats.failures, 0)
	testing.expect_value(t, len(idx.symbols), 0)
}

@(test)
walk_missing_path_test :: proc(t: ^testing.T) {
	root, ok := make_test_tree(t, "odin-lens-m6-missing")
	if !ok {
		return
	}
	defer delete(root, context.allocator)
	defer os.remove_all(root)

	missing, join_err := os.join_path({root, "does-not-exist.odin"}, context.allocator)
	if !testing.expectf(t, join_err == nil, "join_path: %v", join_err) {
		return
	}
	defer delete(missing, context.allocator)

	arenas: Index_Arenas
	index_arenas_init(&arenas, context.allocator)
	defer index_arenas_destroy(&arenas)

	idx, init_err := index_init(index_arenas_index_allocator(&arenas))
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return
	}
	defer index_destroy(&idx, index_arenas_index_allocator(&arenas))

	_, walk_err := index_path(missing, &idx, &arenas)
	testing.expect(t, walk_err != nil, "a missing root must return an error")
}

Warning_State :: struct {
	count: int,
	line:  int,
}

record_warning :: proc(user_data: rawptr, path: string, line, column: int, err: Index_Error) {
	state := (^Warning_State)(user_data)
	state.count += 1
	state.line = line
	_ = path
	_ = column
	_ = err
}

@(test)
walk_lex_error_continues_test :: proc(t: ^testing.T) {
	root, ok := make_test_tree(t, "odin-lens-m6-lex")
	if !ok {
		return
	}
	defer delete(root, context.allocator)
	defer os.remove_all(root)

	if !write_tree_file(t, root, "bad.odin", "package bad\n\nBad :: \"\\q\"\n") ||
	   !write_tree_file(t, root, "good.odin", "package good\n\nGood :: 1\n") {
		return
	}

	arenas: Index_Arenas
	index_arenas_init(&arenas, context.allocator)
	defer index_arenas_destroy(&arenas)

	idx, init_err := index_init(index_arenas_index_allocator(&arenas))
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return
	}
	defer index_destroy(&idx, index_arenas_index_allocator(&arenas))

	state: Warning_State
	stats, walk_err := index_path(
		root,
		&idx,
		&arenas,
		Walk_Options{on_error = record_warning, user_data = &state},
	)
	if !testing.expectf(t, walk_err == nil, "index_path(%s): %v", root, walk_err) {
		return
	}

	testing.expect_value(t, stats.files, 2)
	testing.expect_value(t, stats.failures, 0)
	testing.expect_value(t, state.count, 1)
	testing.expect_value(t, state.line, 3)
	testing.expect(t, has_symbol(&idx, .Constant, "Good"), "the good file must still be indexed")
	testing.expect(
		t,
		has_symbol(&idx, .Constant, "Bad"),
		"the bad file still yields its declaration",
	)
}
