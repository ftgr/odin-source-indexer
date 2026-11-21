package index

import "core:mem"
import "core:strings"

// Symbol_Kind is the declaration category recorded at brace depth 0.
Symbol_Kind :: enum u8 {
	Package,
	Import,
	Procedure,
	Struct,
	Union,
	Enum,
	Bit_Set,
	Type,
	Constant,
	Variable,
}

// Symbol is one top-level declaration. name and file are owned by the Index
// that produced them; index_destroy frees both.
Symbol :: struct {
	name:   string,
	kind:   Symbol_Kind,
	file:   string,
	line:   int,
	column: int,
}

// Index is an append-only collection of symbols. allocator owns the symbol
// slice, every name, and every file path; free it with index_destroy using the
// same allocator.
Index :: struct {
	symbols: [dynamic]Symbol,
}

// index_init returns an empty Index. The caller owns it and frees it with
// index_destroy(&idx, allocator).
index_init :: proc(allocator: mem.Allocator) -> (idx: Index, err: mem.Allocator_Error) {
	idx.symbols, err = make([dynamic]Symbol, allocator)
	return
}

// index_add clones name and file into allocator and appends a Symbol. On
// failure nothing is appended and no memory is leaked.
index_add :: proc(
	idx: ^Index,
	name: string,
	kind: Symbol_Kind,
	file: string,
	line, column: int,
	allocator: mem.Allocator,
) -> mem.Allocator_Error {
	owned_name, name_err := strings.clone(name, allocator)
	if name_err != nil {
		return name_err
	}
	owned_file, file_err := strings.clone(file, allocator)
	if file_err != nil {
		delete(owned_name, allocator)
		return file_err
	}

	_, append_err := append(
		&idx.symbols,
		Symbol{name = owned_name, kind = kind, file = owned_file, line = line, column = column},
	)
	if append_err != nil {
		delete(owned_name, allocator)
		delete(owned_file, allocator)
		return append_err
	}
	return nil
}

// index_destroy frees every owned string and the symbol slice. allocator must
// be the one passed to index_init and index_add.
index_destroy :: proc(idx: ^Index, allocator: mem.Allocator) {
	for sym in idx.symbols {
		delete(sym.name, allocator)
		delete(sym.file, allocator)
	}
	// A dynamic array remembers the allocator it was created with.
	delete(idx.symbols)
	idx^ = {}
}
