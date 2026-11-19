package lexer

import "core:testing"

@(test)
keyword_classification_test :: proc(t: ^testing.T) {
	// Every kind between the keyword sentinels must round-trip through its
	// spelling. This also catches a keyword missing from token_strings: its
	// entry would be "" and keyword_kind would reject it.
	for i in int(Token_Kind._KeywordBegin) + 1 ..< int(Token_Kind._KeywordEnd) {
		kind := Token_Kind(i)
		text := token_strings[kind]

		got, ok := keyword_kind(text)
		testing.expectf(t, ok, "keyword_kind(%q) should succeed", text)
		testing.expect_value(t, got, kind, value_expr = text)
	}

	// Keywords are matched exactly, not as prefixes of longer identifiers.
	cases := []struct {
		text: string,
		want: Token_Kind,
		ok:   bool,
	} {
		{"proc", .proc_, true},
		{"procedure", .Invalid, false},
		{"for", .for_, true},
		{"foreach", .Invalid, false},
		{"", .Invalid, false},
		{"Proc", .Invalid, false},
	}

	for c in cases {
		got, ok := keyword_kind(c.text)
		testing.expect_value(t, ok, c.ok, value_expr = c.text)
		testing.expect_value(t, got, c.want, value_expr = c.text)
	}
}

@(test)
whitespace_skip_test :: proc(t: ^testing.T) {
	c := cursor_init(" \t\r\n  x")
	skip_whitespace(&c)
	testing.expect_value(t, c.position, 6)
	testing.expect_value(t, c.line, 2)
	testing.expect_value(t, c.column, 3)

	r, _ := cursor_peek(&c)
	testing.expect_value(t, r, 'x')

	// Nothing to skip: position and location stay put.
	clean := cursor_init("abc")
	skip_whitespace(&clean)
	testing.expect_value(t, clean.position, 0)
	testing.expect_value(t, clean.line, 1)
	testing.expect_value(t, clean.column, 1)

	// An all-whitespace source ends at EOF.
	blank := cursor_init("  \n")
	skip_whitespace(&blank)
	testing.expect(t, cursor_eof(&blank), "whitespace-only source should be EOF")
	testing.expect_value(t, blank.line, 2)
	testing.expect_value(t, blank.column, 1)
}

@(test)
identifier_scan_test :: proc(t: ^testing.T) {
	cases := []struct {
		src:      string,
		text:     string,
		kind:     Token_Kind,
		position: int,
	} {
		{"abc", "abc", .Ident, 3},
		{"_", "_", .Ident, 1},
		{"_1", "_1", .Ident, 2},
		{"éclair", "éclair", .Ident, 7}, // é is two bytes
		{"日本語", "日本語", .Ident, 9}, // three bytes per rune
		{"for", "for", .for_, 3},
		{"foreach", "foreach", .Ident, 7},
		{"for_", "for_", .Ident, 4},
		{"Proc", "Proc", .Ident, 4},
		{"abc.def", "abc", .Ident, 3}, // stops at the delimiter
	}

	for c in cases {
		cursor := cursor_init(c.src)
		tok, ok := scan_identifier(&cursor)
		testing.expect_value(t, ok, true, value_expr = c.src)
		testing.expect_value(t, tok.kind, c.kind, value_expr = c.src)
		testing.expect_value(t, tok.text, c.text, value_expr = c.src)
		testing.expect_value(t, cursor.position, c.position, value_expr = c.src)
		testing.expect_value(t, tok.byte_offset, 0, value_expr = c.src)
		testing.expect_value(t, tok.line, 1, value_expr = c.src)
		testing.expect_value(t, tok.column, 1, value_expr = c.src)
	}
}

@(test)
identifier_reject_test :: proc(t: ^testing.T) {
	// A failed identifier scan must not consume anything: the number and
	// punctuation paths start from the same position.
	for src in ([]string{"", "1abc", " ", "+", "€"}) {
		c := cursor_init(src)
		_, ok := scan_identifier(&c)
		testing.expect_value(t, ok, false, value_expr = src)
		testing.expect_value(t, c.position, 0, value_expr = src)
		testing.expect_value(t, c.line, 1, value_expr = src)
		testing.expect_value(t, c.column, 1, value_expr = src)
	}
}

@(test)
operator_longest_match_test :: proc(t: ^testing.T) {
	cases := []struct {
		src:    string,
		kind:   Token_Kind,
		length: int,
	} {


		// The ordering traps from GUIDE.md: three-byte forms win over two-byte
		// forms, which win over one-byte forms.
		{"---", .Uninit, 3},
		{"--", .Decrement, 2},
		{"-", .Sub, 1},
		{"->", .ArrowRight, 2},
		{"..=", .RangeFull, 3},
		{"..<", .RangeHalf, 3},
		{"..", .Ellipsis, 2},
		{".", .Period, 1},
		{"&&=", .CmpAndEq, 3},
		{"&&", .CmpAnd, 2},
		{"&~=", .AndNotEq, 3},
		{"&~", .AndNot, 2},
		{"&=", .AndEq, 2},
		{"<<=", .ShlEq, 3},
		{"<<", .Shl, 2},
		{"<=", .LtEq, 2},
		{"<", .Lt, 1},
		{"%%=", .ModModEq, 3},
		{"%%", .ModMod, 2},
		{"%=", .ModEq, 2},
		{"%", .Mod, 1},
		// '::' and ':=' are two tokens, not one.
		{"::", .Colon, 1},
		{":=", .Colon, 1},
	}

	for c in cases {
		cursor := cursor_init(c.src)
		tok, ok := scan_operator(&cursor)
		testing.expect_value(t, ok, true, value_expr = c.src)
		testing.expect_value(t, tok.kind, c.kind, value_expr = c.src)
		testing.expect_value(t, len(tok.text), c.length, value_expr = c.src)
		testing.expect_value(t, cursor.position, c.length, value_expr = c.src)
	}
}

@(test)
operator_reject_test :: proc(t: ^testing.T) {
	// Non-operators are left untouched for the other scan paths.
	for src in ([]string{"", "a", "0", "'", "\"", "€"}) {
		c := cursor_init(src)
		_, ok := scan_operator(&c)
		testing.expect_value(t, ok, false, value_expr = src)
		testing.expect_value(t, c.position, 0, value_expr = src)
	}
}

@(test)
operator_table_test :: proc(t: ^testing.T) {
	// Longest first: each entry is at least as long as the next one.
	for i in 0 ..< len(operator_table) - 1 {
		testing.expect(
			t,
			len(operator_table[i].text) >= len(operator_table[i + 1].text),
			"operator_table must be ordered longest first",
		)
	}

	// Every operator kind appears exactly once and is spelled as token_strings
	// says. This catches a typo in the table and a kind added to the enum but
	// forgotten here.
	for k in Token_Kind(int(Token_Kind._OperatorBegin) + 1) ..< Token_Kind._OperatorEnd {
		if token_strings[k] == "" {
			continue // sentinel (_AssignOpBegin, _AssignOpEnd, ...)
		}
		count := 0
		for entry in operator_table {
			if entry.kind == k {
				count += 1
				testing.expect_value(t, entry.text, token_strings[k])
			}
		}
		testing.expectf(t, count == 1, "operator kind %v must appear once, found %d", k, count)
	}
}

@(test)
tokenize_test :: proc(t: ^testing.T) {
	tokens, err := tokenize("for x := y\n", context.allocator)
	testing.expect(t, err == nil, "tokenize should succeed")
	defer delete(tokens, context.allocator)

	want := []struct {
		kind: Token_Kind,
		text: string,
	}{{.for_, "for"}, {.Ident, "x"}, {.Colon, ":"}, {.Eq, "="}, {.Ident, "y"}}

	if !testing.expect_value(t, len(tokens), len(want)) {
		return
	}

	for tok, i in tokens {
		testing.expect_value(t, tok.kind, want[i].kind, value_expr = tok.text)
		testing.expect_value(t, tok.text, want[i].text)
	}

	// Locations point at the token, not at the whitespace before it.
	testing.expect_value(t, tokens[0].byte_offset, 0)
	testing.expect_value(t, tokens[1].byte_offset, 4)
	testing.expect_value(t, tokens[1].column, 5)
	testing.expect_value(t, tokens[4].byte_offset, 9)
	testing.expect_value(t, tokens[4].column, 10)
}
