package main

import "core:os"
import "core:testing"

@(test)
count_lines_cases :: proc(t: ^testing.T) {
	cases := []struct {
		input: string,
		want:  int,
	}{{"", 0}, {"a", 1}, {"a\n", 1}, {"a\nb", 2}, {"a\n\n", 2}, {"\n", 1}, {"a\nb\nc", 3}}

	buffer: [64]byte
	for c in cases {
		n := copy(buffer[:], c.input)
		got := count_lines(buffer[:n])
		testing.expect_value(t, got, c.want, value_expr = c.input)
	}
}

@(test)
read_source_reads_file :: proc(t: ^testing.T) {
	path := ".odin-source-indexer-read-source.tmp"
	payload := "one\ntwo\nthree\n"

	write_err := os.write_entire_file_from_string(path, payload)
	defer os.remove(path)
	if !testing.expectf(t, write_err == nil, "could not write fixture %s: %v", path, write_err) {
		return
	}

	data, size, err := read_source(path, context.allocator)
	if !testing.expectf(t, err == nil, "read_source(%s): %v", path, err) {
		return
	}
	defer delete(data, context.allocator)

	testing.expect_value(t, size, i64(len(payload)))
	testing.expect_value(t, string(data), payload)
	testing.expect_value(t, count_lines(data), 3)
}

@(test)
read_source_missing_path :: proc(t: ^testing.T) {
	data, size, err := read_source(".odin-source-indexer-does-not-exist.tmp", context.allocator)
	testing.expect(t, err != nil, "a missing path must return an error")
	testing.expect(t, data == nil, "no data is returned on error")
	testing.expect_value(t, size, i64(0))
}
