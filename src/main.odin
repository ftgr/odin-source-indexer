package main

// import "core:fmt"
import "core:os"

// import lx "lexer"
// import id "index"

// M0 skeleton. Replace this with real CLI dispatch in M1 (see GUIDE.md).
main :: proc() {
	error_code := validate_command(os.args)
	if error_code != 0 {
		os.exit(error_code)
	}
}
