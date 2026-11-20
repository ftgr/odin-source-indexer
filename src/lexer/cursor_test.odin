package lexer

import "core:testing"
import "core:unicode/utf8"

// A cursor over an empty source is already at EOF: peek and advance report a
// zero-size rune and leave position, line, and column untouched.
@(test)
cursor_empty_source_test :: proc(t: ^testing.T) {
	c := cursor_init("")

	testing.expect(t, cursor_eof(c), "empty source should be EOF immediately")
	testing.expect_value(t, c.position, 0)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 1)

	r, size := cursor_peek(c)
	testing.expect_value(t, r, utf8.RUNE_ERROR)
	testing.expect_value(t, size, 0)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, utf8.RUNE_ERROR)
	testing.expect_value(t, size, 0)
	testing.expect_value(t, c.position, 0)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 1)
}

// peek reads without consuming; advance consumes exactly one byte for ASCII.
@(test)
cursor_ascii_walk_test :: proc(t: ^testing.T) {
	c := cursor_init("abc")

	r, size := cursor_peek(c)
	testing.expect_value(t, r, 'a')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 0) // peek must not consume
	testing.expect_value(t, c.column, 1)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, 'a')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 1)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 2)

	r, _ = cursor_advance(&c)
	testing.expect_value(t, r, 'b')
	testing.expect_value(t, c.position, 2)
	testing.expect_value(t, c.column, 3)

	r, _ = cursor_advance(&c)
	testing.expect_value(t, r, 'c')
	testing.expect_value(t, c.position, 3)
	testing.expect_value(t, c.column, 4)
	testing.expect(t, cursor_eof(c), "cursor should be at EOF after three runes")
}

// position moves by bytes while column moves by runes: aé😀 is 7 bytes and 3
// runes wide.
@(test)
cursor_utf8_walk_test :: proc(t: ^testing.T) {
	c := cursor_init("aé😀")

	r, size := cursor_peek(c)
	testing.expect_value(t, r, 'a')
	testing.expect_value(t, size, 1)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, 'a')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 1)
	testing.expect_value(t, c.column, 2)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, 'é')
	testing.expect_value(t, size, 2)
	testing.expect_value(t, c.position, 3)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 3)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, '😀')
	testing.expect_value(t, size, 4)
	testing.expect_value(t, c.position, 7)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 4)

	testing.expect(t, cursor_eof(c), "cursor should be at EOF after three runes")
}

// A newline resets the column and bumps the line; peeking at it changes
// nothing.
@(test)
cursor_line_reset_test :: proc(t: ^testing.T) {
	c := cursor_init("a\nb")

	r, size := cursor_advance(&c)
	testing.expect_value(t, r, 'a')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 1)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 2)

	r, size = cursor_peek(c)
	testing.expect_value(t, r, '\n')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 1)
	testing.expect_value(t, c.line, 1)
	testing.expect_value(t, c.column, 2)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, '\n')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 2)
	testing.expect_value(t, c.line, 2)
	testing.expect_value(t, c.column, 1)

	r, size = cursor_advance(&c)
	testing.expect_value(t, r, 'b')
	testing.expect_value(t, size, 1)
	testing.expect_value(t, c.position, 3)
	testing.expect_value(t, c.line, 2)
	testing.expect_value(t, c.column, 2)
	testing.expect(t, cursor_eof(c), "cursor should be at EOF after the newline")
}
