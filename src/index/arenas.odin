package index

import "core:mem"

// Index_Arenas owns the two region allocators used by a batch index:
//
//   - index: long-lived symbols, names, and file paths
//   - file:  scratch bytes and tokens, reset after every source file
//
// The caller creates them with index_arenas_init and frees both with
// index_arenas_destroy after the Index is no longer needed.
Index_Arenas :: struct {
	index: mem.Dynamic_Arena,
	file:  mem.Dynamic_Arena,
}

// index_arenas_init initializes both arenas. allocator backs their blocks; no
// memory is reserved until the first allocation.
index_arenas_init :: proc(a: ^Index_Arenas, allocator: mem.Allocator) {
	mem.dynamic_arena_init(&a.index, allocator, allocator)
	mem.dynamic_arena_init(&a.file, allocator, allocator)
}

// index_arenas_destroy frees every block owned by both arenas.
index_arenas_destroy :: proc(a: ^Index_Arenas) {
	mem.dynamic_arena_destroy(&a.index)
	mem.dynamic_arena_destroy(&a.file)
}

// index_arenas_reset_file releases every file-arena allocation at once. Call it
// only after a file's byte and token buffers are dead. Never call it from
// directory recursion: a parent directory's live data must not be freed.
index_arenas_reset_file :: proc(a: ^Index_Arenas) {
	mem.dynamic_arena_reset(&a.file)
}

// index_arenas_index_allocator returns the allocator for symbols, names, and
// file paths. It lives for the whole index.
index_arenas_index_allocator :: proc(a: ^Index_Arenas) -> mem.Allocator {
	return mem.dynamic_arena_allocator(&a.index)
}

// index_arenas_file_allocator returns the per-file scratch allocator.
index_arenas_file_allocator :: proc(a: ^Index_Arenas) -> mem.Allocator {
	return mem.dynamic_arena_allocator(&a.file)
}
