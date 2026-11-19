package lexer

import "core:unicode/utf8"

// Cursor is the lexer's position in the source: the next rune to read plus the
// line and column it sits on. data is borrowed and never mutated.
Cursor :: struct {
	data:     string, /*the whole source, borrowed; never mutated*/
	position: int, /*0-based byte offset of the *next* rune*/
	line:     int, /* 1-based line of the *next* rune*/
	column:   int, /*1-based column of the *next* rune*/
}

cursor_init :: proc(data: string) -> Cursor {
	return {data = data, line = 1, column = 1}
}

cursor_eof :: proc(c: ^Cursor) -> bool {
	return c.position >= len(c.data)
}

cursor_peek :: proc(c: ^Cursor) -> (r: rune, size: int) {
	if cursor_eof(c) {
		return utf8.RUNE_ERROR, 0
	}
	return utf8.decode_rune(c.data[c.position:])
}

cursor_advance :: proc(c: ^Cursor) -> (r: rune, size: int) {
	if cursor_eof(c) {
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
