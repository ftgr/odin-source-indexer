package index

import "../lexer"
import "core:mem"
import "core:testing"

Expected_Symbol :: struct {
	kind: Symbol_Kind,
	name: string,
}

// extract_source tokenizes src and extracts symbols into an Index owned by
// context.allocator. On failure it returns ok=false and leaves nothing to free.
extract_source :: proc(
	t: ^testing.T,
	src: string,
	file := "fixture.odin",
) -> (
	idx: Index,
	ok: bool,
) {
	lex := lexer.lexer_init(src)
	tokens, tokenize_err := lexer.tokenize(&lex, context.allocator)
	if !testing.expectf(t, tokenize_err == nil, "tokenize(%q): %v", src, tokenize_err) {
		return {}, false
	}
	defer delete(tokens, context.allocator)
	if !testing.expect_value(t, lex.error, lexer.Lex_Error.None, value_expr = src) {
		return {}, false
	}

	init_err: mem.Allocator_Error
	idx, init_err = index_init(context.allocator)
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return {}, false
	}

	if extract_err := extract_file(tokens, file, &idx, context.allocator); extract_err != nil {
		testing.expectf(t, false, "extract_file(%q): %v", src, extract_err)
		index_destroy(&idx, context.allocator)
		return {}, false
	}
	return idx, true
}

expect_symbols :: proc(t: ^testing.T, idx: ^Index, want: []Expected_Symbol) {
	if !testing.expect_value(t, len(idx.symbols), len(want)) {
		return
	}
	for sym, i in idx.symbols {
		testing.expect_value(t, sym.kind, want[i].kind, value_expr = sym.name)
		testing.expect_value(t, sym.name, want[i].name)
	}
}

@(test)
symbol_kinds_test :: proc(t: ^testing.T) {
	src := `package demo

import "core:fmt"
import util "core:strings"
import "foo/bar"

Thing :: struct {
	field: int
}

Choice :: union {
	number: int
}

Color :: enum {
	Red,
	Green,
}

Flags :: bit_set[0..<8; u8]

Id :: distinct int
Names :: map[string]int
List :: [dynamic]int
Pointer :: ^int
Maybe :: ?int
Answer :: 42
name: string

foreign import foreign_lib "lib"

add :: proc(a: int, b: int) -> (sum: int) {
	Local :: 1
	return a + b
}
`
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol {
		{.Package, "demo"},
		{.Import, "fmt"},
		{.Import, "util"},
		{.Import, "bar"},
		{.Struct, "Thing"},
		{.Union, "Choice"},
		{.Enum, "Color"},
		{.Bit_Set, "Flags"},
		{.Type, "Id"},
		{.Type, "Names"},
		{.Type, "List"},
		{.Type, "Pointer"},
		{.Type, "Maybe"},
		{.Constant, "Answer"},
		{.Variable, "name"},
		{.Import, "foreign_lib"},
		{.Procedure, "add"},
	}
	expect_symbols(t, &idx, want)
}

@(test)
nested_declarations_test :: proc(t: ^testing.T) {
	src := `package nested

Outer :: struct {
	Inner :: struct {}
	field: int
}

main :: proc() {
	Nested :: proc() {}
	local: int
}

after :: struct {}
`
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol {
		{.Package, "nested"},
		{.Struct, "Outer"},
		{.Procedure, "main"},
		{.Struct, "after"},
	}
	expect_symbols(t, &idx, want)
}

@(test)
symbol_positions_test :: proc(t: ^testing.T) {
	src := "package pos\n\nx :: 1\n\ty: int\n"
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	if !testing.expect_value(t, len(idx.symbols), 3) {
		return
	}

	testing.expect_value(t, idx.symbols[0].name, "pos")
	testing.expect_value(t, idx.symbols[0].line, 1)
	testing.expect_value(t, idx.symbols[0].column, 9)

	testing.expect_value(t, idx.symbols[1].name, "x")
	testing.expect_value(t, idx.symbols[1].line, 3)
	testing.expect_value(t, idx.symbols[1].column, 1)

	testing.expect_value(t, idx.symbols[2].name, "y")
	testing.expect_value(t, idx.symbols[2].line, 4)
	testing.expect_value(t, idx.symbols[2].column, 2) // a tab is one column
}

@(test)
attributes_test :: proc(t: ^testing.T) {
	src := `package attrs

@(private)
hidden :: proc() {}

@(private="file")
also_hidden :: proc() {}
`
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol {
		{.Package, "attrs"},
		{.Procedure, "hidden"},
		{.Procedure, "also_hidden"},
	}
	expect_symbols(t, &idx, want)
}

@(test)
constants_and_variables_test :: proc(t: ^testing.T) {
	src := `package vars

a := 1
b: int
c :: 1
callback: proc(x: int) -> int
`
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol {
		{.Package, "vars"},
		{.Variable, "b"},
		{.Constant, "c"},
		{.Variable, "callback"},
	}
	expect_symbols(t, &idx, want)
}

@(test)
import_names_test :: proc(t: ^testing.T) {
	src := `package imports

import "core:fmt"
import "foo/bar"
import "single"
import alias "x/y"
import "a:b"
`
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol {
		{.Package, "imports"},
		{.Import, "fmt"},
		{.Import, "bar"},
		{.Import, "single"},
		{.Import, "alias"},
		{.Import, "b"},
	}
	expect_symbols(t, &idx, want)
}

@(test)
symbol_ownership_test :: proc(t: ^testing.T) {
	src := "package owned\n\nName :: 1\n"

	data, alloc_err := make([]byte, len(src), context.allocator)
	if !testing.expectf(t, alloc_err == nil, "make([]byte): %v", alloc_err) {
		return
	}
	defer delete(data, context.allocator)
	copy(data, src)

	lex := lexer.lexer_init(string(data))
	tokens, tokenize_err := lexer.tokenize(&lex, context.allocator)
	if !testing.expectf(t, tokenize_err == nil, "tokenize: %v", tokenize_err) {
		return
	}
	defer delete(tokens, context.allocator)

	idx, init_err := index_init(context.allocator)
	if !testing.expectf(t, init_err == nil, "index_init: %v", init_err) {
		return
	}
	defer index_destroy(&idx, context.allocator)

	if extract_err := extract_file(tokens, "owned.odin", &idx, context.allocator);
	   extract_err != nil {
		testing.expectf(t, false, "extract_file: %v", extract_err)
		return
	}

	// The source buffer is scratch: overwrite it and the names must survive.
	for i in 0 ..< len(data) {
		data[i] = 0xFF
	}

	if !testing.expect_value(t, len(idx.symbols), 2) {
		return
	}
	testing.expect_value(t, idx.symbols[0].name, "owned")
	testing.expect_value(t, idx.symbols[0].file, "owned.odin")
	testing.expect_value(t, idx.symbols[1].name, "Name")
}

@(test)
stray_closing_brace_test :: proc(t: ^testing.T) {
	src := "package braces\n}\nstill :: 1\n"
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol{{.Package, "braces"}, {.Constant, "still"}}
	expect_symbols(t, &idx, want)
}

@(test)
comment_noise_test :: proc(t: ^testing.T) {
	src := `package noisy

// fake :: proc() {}
/* block :: struct {} */
real :: 1
`
	idx, ok := extract_source(t, src)
	if !ok {
		return
	}
	defer index_destroy(&idx, context.allocator)

	want := []Expected_Symbol{{.Package, "noisy"}, {.Constant, "real"}}
	expect_symbols(t, &idx, want)
}
