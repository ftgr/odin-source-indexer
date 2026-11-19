package lexer

import "core:mem"
import "core:unicode"

// Lexical scanning on top of Cursor: whitespace, identifiers, keywords, and
// punctuation. Token definitions live in token.odin; position tracking lives
// in cursor.odin.

is_identifier_start :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_letter(r)
}

is_identifier_continue :: proc(r: rune) -> bool {
	return is_identifier_start(r) || unicode.is_digit(r)
}

skip_whitespace :: proc(c: ^Cursor) {
	for !cursor_eof(c) {
		r, _ := cursor_peek(c)
		switch r {
		case ' ', '\t', '\n', '\r':
			cursor_advance(c)
		case:
			return
		}
	}
}

scan_identifier :: proc(c: ^Cursor) -> (tok: Token, ok: bool) {
	if cursor_eof(c) {
		return {}, false
	}
	r, _ := cursor_peek(c)
	if !is_identifier_start(r) {
		return {}, false
	}

	start := c.position
	start_line := c.line
	start_column := c.column

	for !cursor_eof(c) {
		r, _ = cursor_peek(c)
		if !is_identifier_continue(r) {
			break
		}
		cursor_advance(c)
	}

	tok = Token {
		kind        = .Ident,
		text        = c.data[start:c.position],
		byte_offset = start,
		line        = start_line,
		column      = start_column,
	}
	if kind, found := keyword_kind(tok.text); found {
		tok.kind = kind
	}
	return tok, true
}

Operator :: struct {
	text: string,
	kind: Token_Kind,
}

// Ordered longest first so the first match is always the longest one. Lengths
// are 3, 2, then 1; entries of equal length cannot prefix each other, so their
// relative order is irrelevant. Spellers must match token_strings: the operator
// table test checks both the spelling and the coverage.
operator_table := [?]Operator {
	// 3 bytes
	{"%%=", .ModModEq},
	{"&~=", .AndNotEq},
	{"<<=", .ShlEq},
	{">>=", .ShrEq},
	{"&&=", .CmpAndEq},
	{"||=", .CmpOrEq},
	{"---", .Uninit},
	{"..=", .RangeFull},
	{"..<", .RangeHalf},

	// 2 bytes
	{"%%", .ModMod},
	{"&~", .AndNot},
	{"<<", .Shl},
	{">>", .Shr},
	{"&&", .CmpAnd},
	{"||", .CmpOr},
	{"**", .MulMul},
	{"+=", .AddEq},
	{"-=", .SubEq},
	{"*=", .MulEq},
	{"/=", .QuoEq},
	{"%=", .ModEq},
	{"&=", .AndEq},
	{"|=", .OrEq},
	{"~=", .XorEq},
	{"++", .Increment},
	{"--", .Decrement},
	{"->", .ArrowRight},
	{"==", .CmpEq},
	{"!=", .NotEq},
	{"<=", .LtEq},
	{">=", .GtEq},
	{"..", .Ellipsis},

	// 1 byte
	{"=", .Eq},
	{"!", .Not},
	{"#", .Hash},
	{"@", .At},
	{"$", .Dollar},
	{"^", .Pointer},
	{"?", .Question},
	{"+", .Add},
	{"-", .Sub},
	{"*", .Mul},
	{"/", .Quo},
	{"%", .Mod},
	{"&", .And},
	{"|", .Or},
	{"~", .Xor},
	{"<", .Lt},
	{">", .Gt},
	{"(", .OpenParen},
	{")", .CloseParen},
	{"[", .OpenBracket},
	{"]", .CloseBracket},
	{"{", .OpenBrace},
	{"}", .CloseBrace},
	{":", .Colon},
	{";", .Semicolon},
	{".", .Period},
	{",", .Comma},
	{"\\", .BackSlash},
}

scan_operator :: proc(c: ^Cursor) -> (tok: Token, ok: bool) {
	start := c.position
	start_line := c.line
	start_column := c.column

	rest := c.data[start:]
	for entry in operator_table {
		if len(rest) < len(entry.text) || rest[:len(entry.text)] != entry.text {
			continue
		}
		// Operators are ASCII, so one advance per byte is one rune per column.
		for _ in 0 ..< len(entry.text) {
			cursor_advance(c)
		}
		return Token {
				kind = entry.kind,
				text = c.data[start:c.position],
				byte_offset = start,
				line = start_line,
				column = start_column,
			},
			true
	}
	return {}, false
}

// next returns the next token, skipping whitespace. It always makes progress:
// at EOF it returns .EOF without consuming anything.
next :: proc(c: ^Cursor) -> Token {
	skip_whitespace(c)

	if cursor_eof(c) {
		return Token{kind = .EOF, byte_offset = c.position, line = c.line, column = c.column}
	}

	if tok, ok := scan_identifier(c); ok {
		return tok
	}

	if tok, ok := scan_operator(c); ok {
		return tok
	}

	// Numbers and quoted literals arrive in Milestone 3. Until then, consume
	// one rune so the scan always progresses; invalid UTF-8 lands here too.
	start := c.position
	start_line := c.line
	start_column := c.column
	cursor_advance(c)
	return Token {
		kind = .Invalid,
		text = c.data[start:c.position],
		byte_offset = start,
		line = start_line,
		column = start_column,
	}
}

// tokenize scans data into a newly allocated token slice, excluding the .EOF
// token. The caller owns the result and frees it with delete(tokens, allocator).
// On failure no memory is returned.
tokenize :: proc(
	data: string,
	allocator: mem.Allocator,
) -> (
	tokens: []Token,
	err: mem.Allocator_Error,
) {
	buf, make_err := make([dynamic]Token, allocator)
	if make_err != nil {
		return nil, make_err
	}
	defer if err != nil {
		delete(buf)
	}

	c := cursor_init(data)
	for {
		tok := next(&c)
		if tok.kind == .EOF {
			break
		}
		append(&buf, tok) or_return
	}
	return buf[:], nil
}
