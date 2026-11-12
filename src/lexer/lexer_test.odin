package lexer

import "core:testing"

// M0 placeholder: the lexer itself is still an empty stub. This test only
// proves that the entry points are callable and the harness runs; real token
// assertions replace it in M1/M2 (see GUIDE.md).
@(test)
lexer_mock_test :: proc(t: ^testing.T) {
	lexer()
	tokens()

	testing.expect(t, true, "lexer stub entry points are callable")
}
