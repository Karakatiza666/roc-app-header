import Internal/Lex as Lex

## The header of a Roc app, package or platform, read from the source text.
##
## | Kind | Header | `exposed` | `entries` |
## | --- | --- | --- | --- |
## | `App` | `app [main!] { pf: platform "...", json: "..." }` | `["main!"]` | The record |
## | `Package` | `package [Parser, Utf8] { unicode: "..." }` | `["Parser", "Utf8"]` | The record |
## | `Platform(name)` | `platform "name" requires {...} exposes [...] packages {...} ...` | The `exposes` list | The `packages` record |
##
## A span is a byte range of the source, `start` included, `end` not
## included. An edit changes only the bytes that it must change, and keeps
## comments, order and formatting (a span edit, not a reprint).
Header :: {
	kind : [App, Package, Platform(Str)],
	exposed : List(Str),
	entries : List({ name : Str, value : Str, is_platform : Bool, span : { start : U64, end : U64 }, value_span : { start : U64, end : U64 } }),
	span : { start : U64, end : U64 },
	# The bytes of `{` and `}` of the dependency record. A platform header can have no record.
	record : [Record({ open : U64, close : U64 }), NoRecord],
}.{

	## Reads the header at the start of a source file. Comments and blank
	## lines can come before it. `NoHeader` when the file starts with no
	## header keyword (a headerless app or a type module). `BadHeader` gives the
	## byte offset where the header stops to be valid.
	parse : Str -> Try(Header, [NoHeader, BadHeader({ offset : U64 })])
	parse = |source| {
		bytes = source.to_utf8()
		start = Lex.skip_trivia(bytes, 0)
		after = Lex.word_end(bytes, start)
		keyword = Lex.text(bytes, start, after)
		result =
			if keyword == "app" {
				list_and_record(bytes, start, after, App)
			} else if keyword == "package" {
				list_and_record(bytes, start, after, Package)
			} else if keyword == "platform" {
				platform_header(bytes, start, after)
			} else {
				return Err(NoHeader)
			}
		match result {
			Ok(header) => Ok(header)
			Err(Bad(offset)) => Err(BadHeader({ offset: offset }))
		}
	}

	## `App`, `Package`, or `Platform` with the platform name.
	kind : Header -> [App, Package, Platform(Str)]
	kind = |header| header.kind

	## The names in the list of the header: the app entry points, the package
	## modules, or the platform `exposes` list.
	exposed : Header -> List(Str)
	exposed = |header| header.exposed

	## The entries of the dependency record, in source order. `value` is the
	## text between the quotes, as it is in the source: an escape such as
	## `\u(41)` is not decoded. `is_platform` is true for `pf: platform "..."`.
	## `span` is the entry, from the first byte of the name to the byte after
	## the closing quote. `value_span` is the text between the quotes. A
	## `roc: "<nightly>"` entry is in the list too.
	entries : Header -> List({ name : Str, value : Str, is_platform : Bool, span : { start : U64, end : U64 }, value_span : { start : U64, end : U64 } })
	entries = |header| header.entries

	## The bytes of the header, from the header keyword to the end of its last
	## part.
	span : Header -> { start : U64, end : U64 }
	span = |header| header.span

	## Replaces the text between the quotes of one entry. All other bytes stay
	## the same. `BadValue` when the value has `"`, `\`, `$` or a line break:
	## the edit does not escape.
	set_value : Str, Str, Str -> Try(Str, [NoHeader, BadHeader({ offset : U64 }), NotFound, BadValue])
	set_value = |source, name, value| {
		header = parse(source)?
		entry = match header.entries.find_first(|e| e.name == name) {
			Ok(e) => e
			Err(_) => return Err(NotFound)
		}
		if bad_value(value) {
			return Err(BadValue)
		}
		Ok(splice(source.to_utf8(), entry.value_span, value))
	}

	## Adds a whole entry after the last entry of the dependency record. All
	## other bytes stay. `Exists` when an entry has that name. `BadValue` as for
	## `set_value`. The entry is `name: "value"`, or `name: platform "value"`.
	## A platform header with no `packages` record gives `BadHeader` with the
	## offset of the end of the header.
	##
	## | Record | Result |
	## | --- | --- |
	## | Empty: `{}` | `{ name: "value" }` |
	## | On one line: `{ a: "x" }` | `{ a: "x", name: "value" }` |
	## | On many lines | A new line after the line of the last entry, with the indent of the last entry, and a `,` at its end. A `,` is added after the last entry when it has none. |
	add_entry : Str, { name : Str, value : Str, is_platform : Bool } -> Try(Str, [NoHeader, BadHeader({ offset : U64 }), Exists, BadValue])
	add_entry = |source, entry| {
		header = parse(source)?
		if header.entries.any(|e| e.name == entry.name) {
			return Err(Exists)
		}
		if bad_value(entry.value) {
			return Err(BadValue)
		}
		record = match header.record {
			Record(r) => r
			NoRecord => return Err(BadHeader({ offset: header.span.end }))
		}
		Ok(added(source.to_utf8(), record, header.entries.last(), entry_text(entry)))
	}

	## Removes a whole entry from the dependency record. All other bytes stay,
	## also the comment lines above the entry.
	##
	## | Record | Removed bytes |
	## | --- | --- |
	## | On one line | The entry and one `, ` next to it: `{ a: "x", b: "y" }` gives `{ b: "y" }` or `{ a: "x" }`, and `{ a: "x" }` gives `{}`. |
	## | On many lines | The whole line of the entry, with its line break, its `,` and a comment at its end. |
	remove_entry : Str, Str -> Try(Str, [NoHeader, BadHeader({ offset : U64 }), NotFound])
	remove_entry = |source, name| {
		header = parse(source)?
		entry = match header.entries.find_first(|e| e.name == name) {
			Ok(e) => e
			Err(_) => return Err(NotFound)
		}
		record = match header.record {
			Record(r) => r
			NoRecord => return Err(NotFound)
		}
		bytes = source.to_utf8()
		Ok(splice(bytes, removed_span(bytes, record, header.entries.len(), entry.span), ""))
	}
}

Entry : { name : Str, value : Str, is_platform : Bool, span : { start : U64, end : U64 }, value_span : { start : U64, end : U64 } }

Span : { start : U64, end : U64 }

## `app [...] { ... }` or `package [...] { ... }`. `i` is the index after the keyword.
list_and_record : List(U8), U64, U64, [App, Package, Platform(Str)] -> Try(Header, [Bad(U64)])
list_and_record = |bytes, start, i, kind| {
	list = name_list(bytes, Lex.skip_trivia(bytes, i))?
	open = Lex.skip_trivia(bytes, list.end)
	record = dependency_record(bytes, open)?
	Ok({ kind, exposed: list.names, entries: record.entries, span: { start, end: record.end }, record: Record({ open, close: record.end - 1 }) })
}

## `platform "name"` and its sections in any order. `i` is the index after the keyword.
platform_header : List(U8), U64, U64 -> Try(Header, [Bad(U64)])
platform_header = |bytes, start, i| {
	name_start = Lex.skip_trivia(bytes, i)
	if Lex.at(bytes, name_start) != '"' {
		return Err(Bad(name_start))
	}
	name_end = Lex.string_end(bytes, name_start)?
	var $end = name_end
	var $seen = []
	var $exposed = []
	var $entries = []
	var $record = NoRecord
	while Bool.True {
		k = Lex.skip_trivia(bytes, $end)
		w = Lex.word_end(bytes, k)
		word = Lex.text(bytes, k, w)
		if !sections.contains(word) {
			break
		}
		if $seen.contains(word) {
			return Err(Bad(k))
		}
		$seen = $seen.append(word)
		g = section_body(bytes, word, w)?
		if word == "exposes" {
			list = name_list(bytes, g)?
			$exposed = list.names
			$end = list.end
		} else if word == "packages" {
			record = dependency_record(bytes, g)?
			$entries = record.entries
			$record = Record({ open: g, close: record.end - 1 })
			$end = record.end
		} else {
			$end = Lex.group_end(bytes, g)?
			# The old form `requires {} { ... }` has two records.
			m = Lex.skip_trivia(bytes, $end)
			if word == "requires" and Lex.at(bytes, m) == '{' {
				$end = Lex.group_end(bytes, m)?
			}
		}
	}
	Ok({ kind: Platform(Lex.text(bytes, name_start + 1, name_end - 1)), exposed: $exposed, entries: $entries, span: { start, end: $end }, record: $record })
}

## The keywords of the platform header sections.
sections : List(Str)
sections = ["requires", "exposes", "packages", "provides", "hosted", "targets", "imports"]

## The index of the bracket after a section keyword. `targets` has a `:` before it.
section_body : List(U8), Str, U64 -> Try(U64, [Bad(U64)])
section_body = |bytes, word, w| {
	g = Lex.skip_trivia(bytes, w)
	if word != "targets" {
		return Ok(g)
	}
	if Lex.at(bytes, g) != ':' {
		return Err(Bad(g))
	}
	Ok(Lex.skip_trivia(bytes, g + 1))
}

## `[a, B, c!]` at `i`, with comments and a last `,` allowed.
name_list : List(U8), U64 -> Try({ names : List(Str), end : U64 }, [Bad(U64)])
name_list = |bytes, i| {
	if Lex.at(bytes, i) != '[' {
		return Err(Bad(i))
	}
	var $names = []
	var $i = Lex.skip_trivia(bytes, i + 1)
	while Lex.at(bytes, $i) != ']' {
		end = Lex.word_end(bytes, $i)
		if end == $i {
			return Err(Bad($i))
		}
		$names = $names.append(Lex.text(bytes, $i, end))
		$i = Lex.skip_trivia(bytes, end)
		$i = list_separator(bytes, $i, ']')?
	}
	Ok({ names: $names, end: $i + 1 })
}

## The index after a `,` and the trivia after it, or `i` when the closing bracket is at `i`.
list_separator : List(U8), U64, U8 -> Try(U64, [Bad(U64)])
list_separator = |bytes, i, close| {
	b = Lex.at(bytes, i)
	if b == ',' {
		Ok(Lex.skip_trivia(bytes, i + 1))
	} else if b == close {
		Ok(i)
	} else {
		Err(Bad(i))
	}
}

## `{ name: "value", pf: platform "value" }` at `i`. `end` is the index after `}`.
dependency_record : List(U8), U64 -> Try({ entries : List(Entry), end : U64 }, [Bad(U64)])
dependency_record = |bytes, i| {
	if Lex.at(bytes, i) != '{' {
		return Err(Bad(i))
	}
	var $entries = []
	var $i = Lex.skip_trivia(bytes, i + 1)
	while Lex.at(bytes, $i) != '}' {
		entry = record_entry(bytes, $i)?
		$entries = $entries.append(entry)
		$i = Lex.skip_trivia(bytes, entry.span.end)
		$i = list_separator(bytes, $i, '}')?
	}
	Ok({ entries: $entries, end: $i + 1 })
}

## `name: "value"` or `name: platform "value"` at `i`.
record_entry : List(U8), U64 -> Try(Entry, [Bad(U64)])
record_entry = |bytes, i| {
	name_end = Lex.word_end(bytes, i)
	if name_end == i {
		return Err(Bad(i))
	}
	colon = Lex.skip_trivia(bytes, name_end)
	if Lex.at(bytes, colon) != ':' {
		return Err(Bad(colon))
	}
	k = Lex.skip_trivia(bytes, colon + 1)
	w = Lex.word_end(bytes, k)
	is_platform = Lex.text(bytes, k, w) == "platform"
	quote = if is_platform Lex.skip_trivia(bytes, w) else k
	if Lex.at(bytes, quote) != '"' {
		return Err(Bad(quote))
	}
	end = Lex.string_end(bytes, quote)?
	value_span = { start: quote + 1, end: end - 1 }
	Ok({ name: Lex.text(bytes, i, name_end), value: Lex.text(bytes, value_span.start, value_span.end), is_platform, span: { start: i, end }, value_span })
}

## A value that needs an escape in a string literal. The edits do not escape.
bad_value : Str -> Bool
bad_value = |value| value.to_utf8().any(|b| b == '"' or b == '\\' or b == '$' or b == '\n' or b == '\r')

## The bytes with the span replaced by the text.
splice : List(U8), Span, Str -> Str
splice = |bytes, span, text|
	Str.from_utf8_lossy(bytes.take_first(span.start).concat(text.to_utf8()).concat(bytes.drop_first(span.end)))

## `name: "value"` or `name: platform "value"`.
entry_text : { name : Str, value : Str, is_platform : Bool } -> Str
entry_text = |entry| if entry.is_platform "${entry.name}: platform \"${entry.value}\"" else "${entry.name}: \"${entry.value}\""

## True when the bytes from `start` to `end` are spaces, tabs and line breaks only.
all_space : List(U8), U64, U64 -> Bool
all_space = |bytes, start, end| bytes.sublist({ start, len: if end > start end - start else 0 }).all(|b| Lex.is_blank(b) or b == '\n')

## The text with the new entry after the last entry of the record.
added : List(U8), { open : U64, close : U64 }, Try(Entry, _), Str -> Str
added = |bytes, record, last_entry, text| match last_entry {
	Err(_) =>
		if all_space(bytes, record.open + 1, record.close) {
			splice(bytes, { start: record.open, end: record.close + 1 }, "{ ${text} }")
		} else {
			# Comments only: the entry goes before the `}`.
			splice(bytes, { start: record.close, end: record.close }, "${text} ")
		}

	Ok(last) => {
		after = last.span.end
		comma = Lex.skip_blanks(bytes, after)
		has_comma = Lex.at(bytes, comma) == ','
		eol = Lex.line_end(bytes, after)
		# The new line has the line break of the line of the last entry.
		nl = if eol > 0 and Lex.at(bytes, eol - 1) == '\r' "\r\n" else "\n"
		if !bytes.sublist({ start: record.open, len: record.close - record.open }).contains('\n') {
			# One line.
			splice(bytes, { start: after, end: after }, ", ${text}")
		} else if eol > record.close {
			# Many lines, with the `}` on the line of the last entry.
			at = if has_comma comma + 1 else after
			splice(bytes, { start: at, end: at }, "${if has_comma "" else ","}${nl}${indent(bytes, last.span.start)}${text},")
		} else {
			# Many lines: a new line after the line of the last entry.
			with_line = splice(bytes, { start: eol + 1, end: eol + 1 }, "${indent(bytes, last.span.start)}${text},${nl}")
			if has_comma with_line else splice(with_line.to_utf8(), { start: after, end: after }, ",")
		}
	}
}

## The spaces and tabs at the start of the line of byte `i`.
indent : List(U8), U64 -> Str
indent = |bytes, i| {
	start = Lex.line_start(bytes, i)
	Lex.text(bytes, start, Lex.skip_blanks(bytes, start).min(i))
}

## The bytes that remove_entry removes.
removed_span : List(U8), { open : U64, close : U64 }, U64, Span -> Span
removed_span = |bytes, record, count, entry| {
	# After the entry: blanks, a `,`, blanks, then a comment.
	comma = Lex.skip_blanks(bytes, entry.end)
	has_comma = Lex.at(bytes, comma) == ','
	after_comma = if has_comma Lex.skip_blanks(bytes, comma + 1) else comma
	eol = if Lex.at(bytes, after_comma) == '#' Lex.line_end(bytes, after_comma) else after_comma
	line = Lex.line_start(bytes, entry.start)
	if line > record.open and all_space(bytes, line, entry.start) and Lex.at(bytes, eol) == '\n' and eol < record.close {
		# Many lines: the whole line of the entry.
		{ start: line, end: eol + 1 }
	} else if count == 1 and all_space(bytes, record.open + 1, entry.start) and all_space(bytes, after_comma, record.close) {
		# The only entry: `{}` stays.
		{ start: record.open + 1, end: record.close }
	} else if has_comma {
		{ start: entry.start, end: after_comma }
	} else {
		before = previous_byte(bytes, entry.start)
		if Lex.at(bytes, before) == ',' and before > record.open {
			{ start: before, end: entry.end }
		} else {
			{ start: entry.start, end: entry.end }
		}
	}
}

## The index of the last byte before `i` that is not a space, a tab or a line break.
previous_byte : List(U8), U64 -> U64
previous_byte = |bytes, i| {
	var $i = i
	while $i > 0 and (Lex.is_blank(Lex.at(bytes, $i - 1)) or Lex.at(bytes, $i - 1) == '\n') {
		$i = $i - 1
	}
	if $i > 0 $i - 1 else 0
}
