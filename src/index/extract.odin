package index

import "../lexer"
import "core:mem"

// extract_file scans tokens for top-level declarations and appends them to idx.
// Only brace depth 0 is considered: declarations inside procedures, structs,
// unions, enums, and other blocks are ignored. Comment tokens never reach here
// because the default lexer skips them.
//
// Parenthesis and bracket nesting is skipped too, so procedure parameters and
// named return values are not mistaken for top-level variables.
//
// This is a heuristic, not a parser. It handles the v1 patterns in GUIDE.md M5
// and deliberately classifies anything else after "::" as a Constant (for
// example bit_field and fixed-size array types).
extract_file :: proc(
	tokens: []lexer.Token,
	file: string,
	idx: ^Index,
	allocator: mem.Allocator,
) -> mem.Allocator_Error {
	depth := 0
	paren_depth := 0
	bracket_depth := 0

	for i := 0; i < len(tokens); i += 1 {
		tok := tokens[i]

		// Track nesting before matching. Every block and every parameter list
		// moves the scan out of the top level, where declarations live.
		#partial switch tok.kind {
		case .OpenBrace:
			depth += 1
			continue
		case .CloseBrace:
			if depth > 0 {
				depth -= 1
			}
			continue
		case .OpenParen:
			paren_depth += 1
			continue
		case .CloseParen:
			if paren_depth > 0 {
				paren_depth -= 1
			}
			continue
		case .OpenBracket:
			bracket_depth += 1
			continue
		case .CloseBracket:
			if bracket_depth > 0 {
				bracket_depth -= 1
			}
			continue
		}
		if depth != 0 || paren_depth != 0 || bracket_depth != 0 {
			continue
		}

		#partial switch tok.kind {
		case .package_:
			// package <ident>
			if i + 1 < len(tokens) && tokens[i + 1].kind == .Ident {
				name := tokens[i + 1]
				index_add(
					idx,
					name.text,
					.Package,
					file,
					name.line,
					name.column,
					allocator,
				) or_return
			}
		case .import_:
			// import "<path>" or import <alias> "<path>"
			if name, position, ok := import_declaration(tokens, i); ok {
				index_add(
					idx,
					name,
					.Import,
					file,
					position.line,
					position.column,
					allocator,
				) or_return
			}
		case .Ident:
			if kind, position, ok := identifier_declaration(tokens, i); ok {
				index_add(
					idx,
					position.text,
					kind,
					file,
					position.line,
					position.column,
					allocator,
				) or_return
			}
		}
	}
	return nil
}

// import_declaration reads the name and position of an import starting at the
// import keyword. The alias, when present, is the name; otherwise the last path
// segment is used. position is the alias token or the path string token.
import_declaration :: proc(
	tokens: []lexer.Token,
	i: int,
) -> (
	name: string,
	position: lexer.Token,
	ok: bool,
) {
	if i + 1 >= len(tokens) {
		return
	}

	next := tokens[i + 1]
	#partial switch next.kind {
	case .String:
		path := import_path_name(next.text)
		if path == "" {
			return
		}
		return path, next, true
	case .Ident:
		if i + 2 < len(tokens) && tokens[i + 2].kind == .String {
			return next.text, next, true
		}
	}
	return
}

// import_path_name strips the quotes from a string literal and returns its last
// segment, splitting on both '/' and ':' ("core:fmt" -> "fmt", "a/b" -> "b").
import_path_name :: proc(quoted_path: string) -> string {
	path := quoted_path
	if len(path) >= 2 && (path[0] == '"' || path[0] == '`') && path[len(path) - 1] == path[0] {
		path = path[1:len(path) - 1]
	}

	start := 0
	for i in 0 ..< len(path) {
		if path[i] == '/' || path[i] == ':' {
			start = i + 1
		}
	}
	return path[start:]
}

// identifier_declaration classifies a possible declaration that starts with an
// identifier. It recognizes "name :: <declaration>" and "name : <Type>", and
// deliberately rejects ":=" so assignments are not reported as variables.
identifier_declaration :: proc(
	tokens: []lexer.Token,
	i: int,
) -> (
	kind: Symbol_Kind,
	position: lexer.Token,
	ok: bool,
) {
	if i + 2 >= len(tokens) || tokens[i + 1].kind != .Colon {
		return
	}
	position = tokens[i]

	if tokens[i + 2].kind == .Colon {
		if i + 3 >= len(tokens) {
			return
		}
		kind, ok = classify_declaration(tokens, i + 3)
		return
	}

	// A single colon is a variable, except for the ":=" assignment operator.
	if tokens[i + 2].kind == .Eq {
		return
	}
	return .Variable, position, true
}

// classify_declaration maps the token after "::" to a symbol kind. Anything
// unrecognized is a Constant, matching the M5 heuristic: "<ident> :: anything
// else".
classify_declaration :: proc(tokens: []lexer.Token, i: int) -> (kind: Symbol_Kind, ok: bool) {
	#partial switch tokens[i].kind {
	case .proc_:
		return .Procedure, true
	case .struct_:
		return .Struct, true
	case .union_:
		return .Union, true
	case .enum_:
		return .Enum, true
	case .bit_set_:
		return .Bit_Set, true
	case .distinct_, .map_, .Pointer, .Question:
		return .Type, true
	case .OpenBracket:
		// [dynamic]T is a Type; other bracket forms stay Constants in v1.
		if i + 2 < len(tokens) &&
		   tokens[i + 1].kind == .dynamic_ &&
		   tokens[i + 2].kind == .CloseBracket {
			return .Type, true
		}
		return .Constant, true
	case:
		return .Constant, true
	}
}
