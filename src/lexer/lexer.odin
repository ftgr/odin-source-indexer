package lexer

import "core:mem"
import "core:unicode"

// Lexical scanning on top of Cursor. This file turns source bytes into Tokens:
// whitespace, identifiers and keywords, operators, numeric literals, strings,
// and rune literals. Token definitions live in token.odin; position tracking
// lives in cursor.odin.
//
// Scanning is driven by next, which never fails: it always returns a token and
// always consumes at least one byte unless it is at EOF. Problems are recorded
// once in Lexer.error (first error wins) while the token stream keeps going.
//
// Parameters follow Odin's default: data is passed by value, and ^T appears
// only where a procedure advances the cursor or records an error.

// is_identifier_start reports whether r may begin an identifier. Odin allows an
// underscore or any Unicode letter; digits and combining marks may not start one.
is_identifier_start :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_letter(r)
}

// is_identifier_continue reports whether r may appear after the first character
// of an identifier: the same set as a start, plus Unicode digits.
is_identifier_continue :: proc(r: rune) -> bool {
	return is_identifier_start(r) || unicode.is_digit(r)
}

// is_ascii_digit reports whether r is 0-9. Number scanning uses this instead of
// unicode.is_digit so that, for example, Arabic-Indic digits stay identifiers.
is_ascii_digit :: proc(r: rune) -> bool {
	return r >= '0' && r <= '9'
}

// digit_value returns the numeric value of an ASCII digit in bases up to 16.
// ok is false for anything else; callers compare value against their base to
// reject digits that are legal in hex but not in binary or octal.
digit_value :: proc(r: rune) -> (value: int, ok: bool) {
	switch {
	case r >= '0' && r <= '9':
		return int(r - '0'), true
	case r >= 'a' && r <= 'f':
		return int(r - 'a') + 10, true
	case r >= 'A' && r <= 'F':
		return int(r - 'A') + 10, true
	}
	return 0, false
}

// skip_whitespace advances past spaces, tabs, carriage returns, and newlines.
// This is exactly the compiler's whitespace set; other Unicode spaces are not
// skipped and end up as invalid tokens. Newlines advance the cursor's line
// counter, so the token that follows starts at the right location.
skip_whitespace :: proc(c: ^Cursor) {
	for !cursor_eof(c^) {
		r, _ := cursor_peek(c^)
		switch r {
		case ' ', '\t', '\n', '\r':
			cursor_advance(c)
		case:
			return
		}
	}
}

// scan_identifier scans an identifier or keyword starting at the cursor.
//
// On success it consumes the whole word, resolves keywords through
// keyword_kind, and returns true. If the cursor is at EOF or does not point at
// an identifier start, it consumes nothing and returns false, so next can try
// the other scan paths from the same position.
scan_identifier :: proc(c: ^Cursor) -> (tok: Token, ok: bool) {
	if cursor_eof(c^) {
		return {}, false
	}
	r, _ := cursor_peek(c^)
	if !is_identifier_start(r) {
		return {}, false
	}

	start := c.position
	start_line := c.line
	start_column := c.column

	for !cursor_eof(c^) {
		r, _ = cursor_peek(c^)
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

// Operator is one row of the fixed operator table: the source spelling and the
// token kind it produces.
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

// scan_operator scans the longest operator that starts at the cursor. Operators
// are ASCII, so comparing bytes against the table is enough. It consumes the
// matched spelling and returns true, or leaves the cursor alone and returns
// false when no entry matches.
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

// Lex_Error names the first lexical problem found while scanning. The lexer
// does not stop at an error: it emits an Invalid token and keeps going so the
// token stream stays complete.
Lex_Error :: enum u8 {
	None,
	Invalid_Number,
	Invalid_Escape,
	Invalid_Rune,
	Unterminated_String,
	Unterminated_Raw_String,
	Unterminated_Rune,
}

// Lexer bundles the cursor with the first error seen. error_offset, error_line,
// and error_column point at the cursor position when that error was recorded;
// later errors are ignored so the diagnostic names the original problem.
Lexer :: struct {
	cursor:       Cursor,
	error:        Lex_Error, // first error only
	error_offset: int,
	error_line:   int,
	error_column: int,
}

// lexer_init returns a Lexer positioned at the start of data. The lexer borrows
// data; the caller must keep it alive for as long as the lexer and its tokens
// are used.
lexer_init :: proc(data: string) -> Lexer {
	return {cursor = cursor_init(data)}
}

// lexer_fail_at records err as the lexer's first error at an explicit source
// position. Calls after the first one are ignored, which keeps the diagnostic
// stable when a bad token triggers several checks. Scanners use it to point at
// the start of the malformed token rather than at where scanning gave up.
lexer_fail_at :: proc(l: ^Lexer, err: Lex_Error, offset, line, column: int) {
	if l.error == .None {
		l.error = err
		l.error_offset = offset
		l.error_line = line
		l.error_column = column
	}
}

// lexer_fail records err at the cursor's current position. Use it when the
// offending character is the one under the cursor, such as a bad escape.
lexer_fail :: proc(l: ^Lexer, err: Lex_Error) {
	lexer_fail_at(l, err, l.cursor.position, l.cursor.line, l.cursor.column)
}

// make_token builds a token from the cursor's current position back to start.
// text borrows from the cursor's source buffer; the caller must not free it.
make_token :: proc(c: Cursor, kind: Token_Kind, start, line, column: int) -> Token {
	return Token {
		kind = kind,
		text = c.data[start:c.position],
		byte_offset = start,
		line = line,
		column = column,
	}
}

// eof_token returns an .EOF token at the cursor's current position. It does not
// consume anything; the empty text distinguishes it from a real token.
eof_token :: proc(c: Cursor) -> Token {
	return Token{kind = .EOF, byte_offset = c.position, line = c.line, column = c.column}
}

// invalid_rune consumes one rune and returns it as an .Invalid token. This is
// the fallback for characters no other scanner accepts (including bytes that
// are not valid UTF-8); consuming one rune guarantees next always progresses.
invalid_rune :: proc(c: ^Cursor) -> Token {
	start := c.position
	line := c.line
	column := c.column
	cursor_advance(c)
	return make_token(c^, .Invalid, start, line, column)
}

// next returns the next token, skipping whitespace first. At EOF it returns
// .EOF without consuming anything. Otherwise it dispatches on the first rune:
// identifiers and keywords, numbers, strings, runes, then operators, with
// invalid_rune as the final fallback. Every non-EOF path consumes at least one
// byte, so a caller loop cannot spin.
next :: proc(l: ^Lexer) -> Token {
	c := &l.cursor
	skip_whitespace(c)
	if cursor_eof(c^) {
		return eof_token(c^)
	}

	r, _ := cursor_peek(c^)
	switch {
	case is_identifier_start(r):
		tok, _ := scan_identifier(c) // the start rune guarantees success
		return tok
	case is_ascii_digit(r):
		return scan_number(l)
	case r == '"' || r == '`':
		return scan_string(l)
	case r == '\'':
		return scan_rune(l)
	}
	if tok, ok := scan_operator(c); ok {
		return tok
	}
	return invalid_rune(c) // unknown rune or invalid UTF-8
}

// scan_digit_run consumes digits valid in base plus '_' separators. It returns
// the number of real digits (underscores are not counted) so callers can reject
// prefixes such as "0x" that have no digits after them.
scan_digit_run :: proc(c: ^Cursor, base: int) -> (digits: int) {
	for !cursor_eof(c^) {
		r, _ := cursor_peek(c^)
		if r == '_' {
			cursor_advance(c)
			continue
		}
		value, ok := digit_value(r)
		if !ok || value >= base {
			break
		}
		cursor_advance(c)
		digits += 1
	}
	return
}

// scan_number scans an integer, float, or imaginary literal. It always starts
// on an ASCII digit and consumes the longest valid literal:
//
//   - 0x / 0b / 0o prefixes, with no fraction, exponent, or imaginary suffix;
//   - 0h hex floats (4, 8, or 16 hex digits), which are always .Float;
//   - decimal digits with '_' separators;
//   - a fractional part only when '.' is followed by a digit, so 1..2 stays
//     Integer, Ellipsis, Integer;
//   - an exponent only when 'e'/'E' (with optional sign) is followed by a
//     digit, so 1efoo stays Integer followed by the identifier efoo;
//   - a trailing 'i' marks an imaginary value.
//
// A prefix with no digits (0x, 0b, 0o, 0h) consumes the prefix, records
// Invalid_Number, and returns an .Invalid token. 0h with the wrong number of
// digits records Invalid_Number but keeps the .Float token, matching the
// compiler.
scan_number :: proc(l: ^Lexer) -> Token {
	c := &l.cursor
	start := c.position
	line := c.line
	column := c.column
	kind := Token_Kind.Integer

	// 0x / 0b / 0o / 0h: no fraction, exponent, or imaginary suffix.
	if r, _ := cursor_peek(c^); r == '0' {
		r2, _ := cursor_peek_ahead(c^, 1)

		// 0h is a hexadecimal float, not an integer: the compiler requires
		// exactly 4, 8, or 16 hex digits and still calls the token a float.
		if r2 == 'h' {
			cursor_advance(c)
			cursor_advance(c)
			digits := scan_digit_run(c, 16)
			if digits == 0 {
				lexer_fail_at(l, .Invalid_Number, start, line, column)
				return make_token(c^, .Invalid, start, line, column)
			}
			if digits != 4 && digits != 8 && digits != 16 {
				lexer_fail_at(l, .Invalid_Number, start, line, column)
			}
			return make_token(c^, .Float, start, line, column)
		}

		base := 0
		switch r2 {
		case 'x':
			base = 16
		case 'b':
			base = 2
		case 'o':
			base = 8
		}
		if base != 0 {
			cursor_advance(c)
			cursor_advance(c)
			if scan_digit_run(c, base) == 0 {
				lexer_fail_at(l, .Invalid_Number, start, line, column)
				return make_token(c^, .Invalid, start, line, column)
			}
			return make_token(c^, .Integer, start, line, column)
		}
	}

	scan_digit_run(c, 10)

	// 1..2 must not become a float: the dot needs a digit after it.
	if r, _ := cursor_peek(c^); r == '.' {
		if r2, _ := cursor_peek_ahead(c^, 1); is_ascii_digit(r2) {
			kind = .Float
			cursor_advance(c)
			scan_digit_run(c, 10)
		}
	}

	// 1e9 is a float; 1e + identifier is not.
	if r, _ := cursor_peek(c^); r == 'e' || r == 'E' {
		r2, _ := cursor_peek_ahead(c^, 1)
		has_digits := is_ascii_digit(r2)
		if r2 == '+' || r2 == '-' {
			r3, _ := cursor_peek_ahead(c^, 2)
			has_digits = is_ascii_digit(r3)
		}
		if has_digits {
			kind = .Float
			cursor_advance(c)
			if r, _ = cursor_peek(c^); r == '+' || r == '-' {
				cursor_advance(c)
			}
			scan_digit_run(c, 10)
		}
	}

	if r, _ := cursor_peek(c^); r == 'i' {
		kind = .Imag
		cursor_advance(c)
	}
	return make_token(c^, kind, start, line, column)
}

// scan_escape_digits consumes exactly count digits in base after an escape
// prefix. On a missing or out-of-range digit it records Invalid_Escape, stops
// without consuming the offending rune, and returns false; the enclosing string
// or rune scanner then continues from that rune, so scanning still progresses.
scan_escape_digits :: proc(l: ^Lexer, base, count: int) -> bool {
	c := &l.cursor
	for _ in 0 ..< count {
		if cursor_eof(c^) {
			lexer_fail(l, .Invalid_Escape)
			return false
		}
		r, _ := cursor_peek(c^)
		value, ok := digit_value(r)
		if !ok || value >= base {
			lexer_fail(l, .Invalid_Escape)
			return false
		}
		cursor_advance(c)
	}
	return true
}

// scan_escape consumes the character after a backslash, which the caller has
// already consumed. It validates and consumes the escape but does not decode
// it: the lexer only needs the token span.
//
// Valid forms are the single-character escapes (\a \b \e \f \n \r \t \v \\ \'
// \"), octal escapes of exactly three digits, \x with two hex digits, \u with
// four, and \U with eight. On an unknown or malformed escape it records
// Invalid_Escape, consumes one rune to guarantee progress, and returns false.
scan_escape :: proc(l: ^Lexer) -> bool {
	c := &l.cursor
	r, _ := cursor_peek(c^)
	switch r {
	case 'a', 'b', 'e', 'f', 'n', 'r', 't', 'v', '\\', '\'', '"':
		cursor_advance(c)
		return true
	case '0' ..= '7':
		return scan_escape_digits(l, 8, 3)
	case 'x':
		cursor_advance(c)
		return scan_escape_digits(l, 16, 2)
	case 'u':
		cursor_advance(c)
		return scan_escape_digits(l, 16, 4)
	case 'U':
		cursor_advance(c)
		return scan_escape_digits(l, 16, 8)
	}
	lexer_fail(l, .Invalid_Escape)
	if !cursor_eof(c^) {
		cursor_advance(c) // always progress
	}
	return false
}

// scan_string scans an interpreted ("..."), raw (`...`), or triple-quoted
// ("""...""" / ```...```) string literal.
//
// Single-line interpreted strings process escapes and must close before a raw
// newline; on a newline or EOF they stop without consuming the terminator,
// record Unterminated_String, and return an .Invalid token. Raw strings take
// every byte literally and may span lines. Triple-quoted strings may span lines
// too; the """ form still processes escapes.
//
// The opening quote is consumed first, so even an empty or unterminated literal
// makes progress. Newlines go through cursor_advance, which keeps line and
// column correct for the tokens that follow.
scan_string :: proc(l: ^Lexer) -> Token {
	c := &l.cursor
	start := c.position
	line := c.line
	column := c.column
	quote, _ := cursor_peek(c^) // '"' or '`'
	cursor_advance(c) // opening quote

	// Three consecutive quotes open a multi-line literal. The single-quote
	// scanners below keep their "no raw newline" / "no escapes" rules.
	if r, _ := cursor_peek(c^); r == quote {
		if r2, _ := cursor_peek_ahead(c^, 1); r2 == quote {
			cursor_advance(c)
			cursor_advance(c)
			return scan_triple_string(l, start, line, column, quote)
		}
	}

	if quote == '`' {
		for !cursor_eof(c^) {
			r, _ := cursor_peek(c^)
			cursor_advance(c)
			if r == '`' {
				return make_token(c^, .String, start, line, column)
			}
		}
		lexer_fail_at(l, .Unterminated_Raw_String, start, line, column)
		return make_token(c^, .Invalid, start, line, column)
	}

	ok := true
	for !cursor_eof(c^) {
		r, _ := cursor_peek(c^)
		switch r {
		case '"':
			cursor_advance(c)
			if !ok {
				return make_token(c^, .Invalid, start, line, column)
			}
			return make_token(c^, .String, start, line, column)
		case '\n':
			lexer_fail_at(l, .Unterminated_String, start, line, column)
			return make_token(c^, .Invalid, start, line, column) // newline not consumed
		case '\\':
			cursor_advance(c)
			if !scan_escape(l) {
				ok = false
			}
		case:
			cursor_advance(c)
		}
	}
	lexer_fail_at(l, .Unterminated_String, start, line, column)
	return make_token(c^, .Invalid, start, line, column)
}

// scan_triple_string finishes a triple-quoted literal after its three opening
// quotes have been consumed. It may span lines, and the closing delimiter is
// three consecutive quote runes.
//
// For """ escapes are processed like an interpreted string; for ``` every byte
// is literal. At EOF it records Unterminated_String or Unterminated_Raw_String
// and returns an .Invalid token.
scan_triple_string :: proc(l: ^Lexer, start, line, column: int, quote: rune) -> Token {
	c := &l.cursor
	ok := true
	for !cursor_eof(c^) {
		r, _ := cursor_peek(c^)

		if r == quote {
			r2, _ := cursor_peek_ahead(c^, 1)
			r3, _ := cursor_peek_ahead(c^, 2)
			if r2 == quote && r3 == quote {
				cursor_advance(c)
				cursor_advance(c)
				cursor_advance(c)
				if !ok {
					return make_token(c^, .Invalid, start, line, column)
				}
				return make_token(c^, .String, start, line, column)
			}
		}

		if quote == '"' && r == '\\' {
			cursor_advance(c)
			if !scan_escape(l) {
				ok = false
			}
			continue
		}
		cursor_advance(c)
	}

	if quote == '"' {
		lexer_fail_at(l, .Unterminated_String, start, line, column)
	} else {
		lexer_fail_at(l, .Unterminated_Raw_String, start, line, column)
	}
	return make_token(c^, .Invalid, start, line, column)
}

// scan_rune scans a rune literal: one rune or one escape between single quotes.
//
// The escape case is handled before the closing-quote case, so '\'' does not
// terminate early: the backslash is consumed and scan_escape consumes the
// escaped quote. Empty (''), multi-rune ('ab'), newline, and EOF forms record
// the matching error and return an .Invalid token.
scan_rune :: proc(l: ^Lexer) -> Token {
	c := &l.cursor
	start := c.position
	line := c.line
	column := c.column
	cursor_advance(c) // opening '

	count := 0
	ok := true
	for !cursor_eof(c^) {
		r, _ := cursor_peek(c^)
		switch r {
		case '\'':
			cursor_advance(c)
			if count != 1 || !ok {
				if count != 1 {
					lexer_fail_at(l, .Invalid_Rune, start, line, column)
				}
				return make_token(c^, .Invalid, start, line, column)
			}
			return make_token(c^, .Rune, start, line, column)
		case '\n':
			lexer_fail_at(l, .Unterminated_Rune, start, line, column)
			return make_token(c^, .Invalid, start, line, column)
		case '\\':
			cursor_advance(c)
			if !scan_escape(l) {
				ok = false
			}
			count += 1
		case:
			cursor_advance(c)
			count += 1
		}
	}
	lexer_fail_at(l, .Unterminated_Rune, start, line, column)
	return make_token(c^, .Invalid, start, line, column)
}

// tokenize scans l's source into a newly allocated token slice, excluding the
// .EOF token. The caller owns the result and frees it with
// delete(tokens, allocator); token text still borrows the source buffer.
//
// Only allocation failures are returned. Lexical problems are recorded in
// l.error (and show up as .Invalid tokens), so the caller can report them after
// consuming the stream. On an allocation failure the partial buffer is freed
// and no memory is returned.
tokenize :: proc(
	l: ^Lexer,
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

	for {
		tok := next(l)
		if tok.kind == .EOF {
			break
		}
		append(&buf, tok) or_return
	}
	return buf[:], nil
}
