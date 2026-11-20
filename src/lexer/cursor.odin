package lexer

import "core:unicode/utf8"

// Cursor is the lexer's position in the source: the next rune to read plus the
// line and column it sits on. data is borrowed and never mutated.
//
// Read-only helpers (cursor_eof, cursor_peek, cursor_peek_ahead) take Cursor by
// value; only cursor_advance needs ^Cursor because it moves the position.
Cursor :: struct {
	data:     string, /*the whole source, borrowed; never mutated*/
	position: int, /*0-based byte offset of the *next* rune*/
	line:     int, /* 1-based line of the *next* rune*/
	column:   int, /*1-based column of the *next* rune*/
}

// cursor_init returns a Cursor at the first byte of data, on line 1, column 1.
// It borrows data; the caller owns the buffer.
cursor_init :: proc(data: string) -> Cursor {
	return {data = data, line = 1, column = 1}
}

// cursor_eof reports whether the cursor has consumed the whole source.
cursor_eof :: proc(c: Cursor) -> bool {
	return c.position >= len(c.data)
}

// cursor_peek returns the rune at the cursor without consuming it, plus its
// UTF-8 length in bytes. At EOF it returns (utf8.RUNE_ERROR, 0); invalid UTF-8
// decodes to RUNE_ERROR with size 1.
cursor_peek :: proc(c: Cursor) -> (r: rune, size: int) {
	if cursor_eof(c) {
		return utf8.RUNE_ERROR, 0
	}
	return utf8.decode_rune(c.data[c.position:])
}

// cursor_advance consumes one rune and returns it with its byte length. A
// newline resets the column to 1 and increments the line; every other rune
// increments the column. At EOF it consumes nothing and returns
// (utf8.RUNE_ERROR, 0).
cursor_advance :: proc(c: ^Cursor) -> (r: rune, size: int) {
	if cursor_eof(c^) {
		return utf8.RUNE_ERROR, 0
	}
	r, size = utf8.decode_rune(c.data[c.position:])
	c.position += size
	if r == '\n' {
		c.line += 1
		c.column = 1
	} else {
		c.column += 1
	}
	return
}

// cursor_peek_ahead returns the rune n runes ahead without consuming.
// n == 0 is the current rune; past EOF it returns (RUNE_ERROR, 0).
cursor_peek_ahead :: proc(c: Cursor, n: int) -> (r: rune, size: int) {
	position := c.position
	for _ in 0 ..< n {
		if position >= len(c.data) {
			return utf8.RUNE_ERROR, 0
		}
		_, step := utf8.decode_rune(c.data[position:])
		if step == 0 {
			return utf8.RUNE_ERROR, 0
		}
		position += step
	}
	if position >= len(c.data) {
		return utf8.RUNE_ERROR, 0
	}
	return utf8.decode_rune(c.data[position:])
}
