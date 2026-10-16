## Byte scanners for the header grammar. Each one takes the source bytes and
## an index, and gives the index after the text that it reads.
Lex :: [].{

	## The byte at an index, or 0 after the end.
	at : List(U8), U64 -> U8
	at = |bytes, i| bytes.get(i) ?? 0

	## A space, a tab or a carriage return. Not a line break.
	is_blank : U8 -> Bool
	is_blank = |b| b == ' ' or b == '\t' or b == '\r'

	## A byte of a name: a letter, a digit, `_` or `!`.
	is_word_byte : U8 -> Bool
	is_word_byte = |b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_' or b == '!'

	## The index after the spaces, tabs and carriage returns at `i`.
	skip_blanks : List(U8), U64 -> U64
	skip_blanks = |bytes, i| {
		var $i = i
		while is_blank(at(bytes, $i)) {
			$i = $i + 1
		}
		$i
	}

	## The index of the line break at or after `i`, or the end of the bytes.
	line_end : List(U8), U64 -> U64
	line_end = |bytes, i| {
		var $i = i
		while $i < bytes.len() and at(bytes, $i) != '\n' {
			$i = $i + 1
		}
		$i
	}

	## The index after the last line break before `i`, or 0.
	line_start : List(U8), U64 -> U64
	line_start = |bytes, i| {
		var $i = i
		while $i > 0 and at(bytes, $i - 1) != '\n' {
			$i = $i - 1
		}
		$i
	}

	## The index after the spaces, line breaks and comments at `i`.
	skip_trivia : List(U8), U64 -> U64
	skip_trivia = |bytes, i| {
		var $i = i
		while $i < bytes.len() {
			b = at(bytes, $i)
			if is_blank(b) or b == '\n' {
				$i = $i + 1
			} else if b == '#' {
				$i = line_end(bytes, $i)
			} else {
				break
			}
		}
		$i
	}

	## The index after the name at `i`. It is `i` when no name is there.
	word_end : List(U8), U64 -> U64
	word_end = |bytes, i| {
		var $i = i
		while is_word_byte(at(bytes, $i)) {
			$i = $i + 1
		}
		$i
	}

	## The index after the closing quote of the string that starts at `start`.
	## An interpolation `${...}` can hold strings and brackets.
	string_end : List(U8), U64 -> Try(U64, [Bad(U64)])
	string_end = |bytes, start| {
		var $i = start + 1
		while $i < bytes.len() {
			b = at(bytes, $i)
			if b == '"' {
				return Ok($i + 1)
			} else if b == '\n' {
				return Err(Bad($i))
			} else if b == '\\' {
				if at(bytes, $i + 1) == '\n' {
					return Err(Bad($i + 1))
				}
				$i = $i + 2
			} else if b == '$' and at(bytes, $i + 1) == '{' {
				$i = group_end(bytes, $i + 1)?
			} else {
				$i = $i + 1
			}
		}
		Err(Bad(bytes.len()))
	}

	## The index after the closing quote of a character literal at `start`, or
	## the line break when it has no closing quote.
	char_end : List(U8), U64 -> U64
	char_end = |bytes, start| {
		var $i = if at(bytes, start + 1) == '\\' start + 3 else start + 2
		while $i < bytes.len() and at(bytes, $i) != '\'' and at(bytes, $i) != '\n' {
			$i = $i + 1
		}
		if at(bytes, $i) == '\'' $i + 1 else $i
	}

	## The index after the bracket that closes the bracket at `start`. Strings,
	## character literals and comments in the group are skipped.
	group_end : List(U8), U64 -> Try(U64, [Bad(U64)])
	group_end = |bytes, start| {
		if closer(at(bytes, start)) == 0 {
			return Err(Bad(start))
		}
		var $open = []
		var $i = start
		while $i < bytes.len() {
			b = at(bytes, $i)
			if closer(b) != 0 {
				$open = $open.append(closer(b))
				$i = $i + 1
			} else if b == '}' or b == ']' or b == ')' {
				if $open.last() != Ok(b) {
					return Err(Bad($i))
				}
				$open = $open.drop_last(1)
				$i = $i + 1
				if $open.is_empty() {
					return Ok($i)
				}
			} else if b == '"' {
				$i = string_end(bytes, $i)?
			} else if b == '\'' {
				$i = char_end(bytes, $i)
			} else if b == '#' or (b == '\\' and at(bytes, $i + 1) == '\\') {
				# A comment or a line of a multi-line string goes to the end of the line.
				$i = line_end(bytes, $i)
			} else {
				$i = $i + 1
			}
		}
		Err(Bad(bytes.len()))
	}

	## The closing bracket of an opening bracket, or 0.
	closer : U8 -> U8
	closer = |b| if b == '{' '}' else if b == '[' ']' else if b == '(' ')' else 0

	## The bytes from `start` to `end` as text.
	text : List(U8), U64, U64 -> Str
	text = |bytes, start, end| Str.from_utf8_lossy(bytes.sublist({ start, len: if end > start end - start else 0 }))
}
