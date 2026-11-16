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
