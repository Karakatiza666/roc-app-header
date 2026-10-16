app [main!] { pkg: "../package/main.roc" }

import pkg.Header

main! = |_args| Ok({})

## Parse a header that a test knows to be good.
parsed : Str -> Header
parsed = |source| match Header.parse(source) {
	Ok(h) => h
	Err(_) => crash "test header did not parse"
}

## The entries as (name, value, is_platform), in source order.
triples : Str -> List((Str, Str, Bool))
triples = |source| parsed(source).entries().map(|e| (e.name, e.value, e.is_platform))

## The bytes of a span as text.
slice : Str, { start : U64, end : U64 } -> Str
slice = |source, span| Str.from_utf8(source.to_utf8().sublist({ start: span.start, len: span.end - span.start })) ?? ""

## True for the result `Err(NoHeader)`.
no_header : Try(Header, [NoHeader, BadHeader({ offset : U64 })]) -> Bool
no_header = |result| match result {
	Err(NoHeader) => Bool.True
	_ => Bool.False
}

## The text before and after the header.
outside : Str -> (Str, Str)
outside = |source| {
	sp = parsed(source).span()
	(slice(source, { start: 0, end: sp.start }), slice(source, { start: sp.end, end: source.count_utf8_bytes() }))
}

## The text before and after the value span of one entry.
around_value : Str, Str -> (Str, Str)
around_value = |source, name| match parsed(source).entries().find_first(|e| e.name == name) {
	Ok(e) => (slice(source, { start: 0, end: e.value_span.start }), slice(source, { start: e.value_span.end, end: source.count_utf8_bytes() }))
	Err(_) => crash "no entry ${name}"
}

cli = "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst"

cli_29 = "https://github.com/roc-lang/basic-cli/releases/download/0.29.0/GrSTLEKd6yw8orQ5ByQQVY3Htg59vZYaoHBvQELueiMB.tar.zst"

json = "https://github.com/someone/roc-json/releases/download/2.1.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst"

json_new = "https://github.com/someone/roc-json/releases/download/2.2.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst"

parser = "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst"

## The app header of Design 4.2, with a comment line, then the rest of the file.
app_src =
	\\## An app.
	\\app [main!] {
	\\	pf: platform "${cli}",
	\\	# JSON for the config file
	\\	json: "${json}",
	\\	util: "../util/main.roc",
	\\	roc: "nightly-2026-10-09-258ab27",
	\\}
	\\
	\\import pf.Stdout
	\\import json.Json
	\\
	\\main! = |_args| Stdout.line!("hi")

## A package header on one line, as in layout-probe.
pkg_src =
	\\package [Hex, Pair] { parser: "${parser}" }
	\\
	\\import Internal/Nibble as Nibble

## The platform header of the roc-syntax `platforms` topic.
platform_src =
	\\platform "my-platform"
	\\	requires { main! : List(Str) => Try({}, [Exit(I32), ..]) }
	\\	exposes [Cmd, Stdout]
	\\	packages {
	\\		json: "${json}",
	\\	}
	\\	provides { "roc_main": main_for_host! }
	\\	hosted { "roc_read_file": File.read_bytes! }
	\\	targets: {
	\\		inputs_dir: "targets/",
	\\		x64musl: { inputs: ["crt1.o", "libhost.a", app] },
	\\	}
	\\
	\\import Stdout

# R-PK5, Design 4.2: the kind, the entry point list and the entries of an app header, in source order
expect {
	h = parsed(app_src)
	h.kind() == App and h.exposed() == ["main!"]
}

# R-PK5, R-H7, Design 4.2: a platform entry, a URL entry, a path entry and the roc: pin are entries
expect triples(app_src) == [("pf", cli, Bool.True), ("json", json, Bool.False), ("util", "../util/main.roc", Bool.False), ("roc", "nightly-2026-10-09-258ab27", Bool.False)]

# R-PK5: a package header on one line
expect {
	h = parsed(pkg_src)
	h.kind() == Package and h.exposed() == ["Hex", "Pair"] and triples(pkg_src) == [("parser", parser, Bool.False)]
}

# R-PK5: a platform header gives its name, its exposes list, and the entries of its packages record
expect {
	h = parsed(platform_src)
	h.kind() == Platform("my-platform") and h.exposed() == ["Cmd", "Stdout"] and triples(platform_src) == [("json", json, Bool.False)]
}

# R-PK5, roc-syntax `packages` topic: a package header can name a platform
expect triples("package [FxHttp] { pf: platform \"${cli}\" }") == [("pf", cli, Bool.True)]

# R-PK5, roc-syntax `app_header` topic: an app header with no platform and no entries
expect {
	src = "app [main!] {}\n\nmain! = |_args| Ok({})\n"
	h = parsed(src)
	h.kind() == App and h.entries() == []
}

# R-PK5, roc-syntax `app_header` topic: a headerless app has no header
expect no_header(Header.parse("main! = |_args| {\n\techo!(\"Hello\")\n\tOk({})\n}\n"))

# R-PK5, roc-syntax `modules` topic: a type module has no header
expect no_header(Header.parse("import Internal/Nibble as Nibble\n\nHex :: [].{\n\tx = 1\n}\n"))

# R-PK5: text that starts with a header keyword but is not a header is an error, not a crash
expect Header.parse("app [main!] { pf: platform ").is_err()

# R-H1: the header span starts at the keyword after the comment, and ends at the closing brace
expect outside(app_src) == ("## An app.\n", "\n\nimport pf.Stdout\nimport json.Json\n\nmain! = |_args| Stdout.line!(\"hi\")")

# R-H1: the header span of a platform ends after its last part (targets)
expect outside(platform_src).1 == "\n\nimport Stdout"

# R-H1: set_value changes only the text between the quotes. All other bytes stay.
expect {
	(before, after) = around_value(app_src, "json")
	Header.set_value(app_src, "json", json_new) == Ok("${before}${json_new}${after}")
}

# R-H1, R-AD31: set_value on the platform entry keeps the platform keyword
expect {
	(before, after) = around_value(app_src, "pf")
	out = Header.set_value(app_src, "pf", cli_29)
	out == Ok("${before}${cli_29}${after}") and (out.map_ok(triples) ?? []).first() == Ok(("pf", cli_29, Bool.True))
}

# R-H1, R-H6: set_value writes a new roc: pin
expect {
	(before, after) = around_value(app_src, "roc")
	Header.set_value(app_src, "roc", "nightly-2026-10-15-0000000") == Ok("${before}nightly-2026-10-15-0000000${after}")
}

# R-H1: set_value on a one-line package header
expect {
	(before, after) = around_value(pkg_src, "parser")
	Header.set_value(pkg_src, "parser", json) == Ok("${before}${json}${after}")
}

# R-H1: set_value of a name that is not in the header
expect Header.set_value(app_src, "nope", json) == Err(NotFound)

# R-H1: set_value on a file with no header
expect Header.set_value("x = 1\n", "json", json) == Err(NoHeader)

# R-H1, R-RV1: remove_entry removes the entry and moves no other entry
expect {
	out = Header.remove_entry(app_src, "json") ?? ""
	triples(out) == [("pf", cli, Bool.True), ("util", "../util/main.roc", Bool.False), ("roc", "nightly-2026-10-09-258ab27", Bool.False)]
}

# R-H1, R-RV1: remove_entry keeps the bytes outside the header and the text of each other entry
expect {
	out = Header.remove_entry(app_src, "util") ?? ""
	h = parsed(app_src)
	others = h.entries().keep_if(|e| e.name != "util").map(|e| slice(app_src, e.span))
	outside(out) == outside(app_src) and others.all(|text| out.contains(text))
}

# R-H1: remove_entry of a name that is not in the header
expect Header.remove_entry(app_src, "nope") == Err(NotFound)

# R-H1: remove_entry of the last entry of a one-line header leaves a header with no entries
expect triples(Header.remove_entry(pkg_src, "parser") ?? "") == []

# R-H1, R-AD24: add_entry adds the entry, and the old entries stay in their order
expect {
	out = Header.add_entry(app_src, { name: "parser", value: parser, is_platform: Bool.False }) ?? ""
	t = triples(out)
	t.keep_if(|(n, _, _)| n != "parser") == triples(app_src) and t.contains(("parser", parser, Bool.False))
}

# R-H1: add_entry keeps the bytes outside the header, the comment, and the text of each old entry
expect {
	out = Header.add_entry(app_src, { name: "parser", value: parser, is_platform: Bool.False }) ?? ""
	old = parsed(app_src).entries().map(|e| slice(app_src, e.span))
	outside(out) == outside(app_src) and out.contains("# JSON for the config file") and old.all(|text| out.contains(text))
}

# R-H1, R-AD30: add_entry of a platform entry to an app with no platform
expect {
	src = "app [main!] { json: \"${json}\" }\n"
	out = Header.add_entry(src, { name: "pf", value: cli, is_platform: Bool.True }) ?? ""
	triples(out).contains(("pf", cli, Bool.True))
}

# R-H1: add_entry to a header with an empty record
expect {
	src = "app [main!] {}\n\nmain! = |_args| Ok({})\n"
	out = Header.add_entry(src, { name: "json", value: json, is_platform: Bool.False }) ?? ""
	triples(out) == [("json", json, Bool.False)] and outside(out) == outside(src)
}

# R-H1, R-AD18: add_entry with a name that is in the header
expect Header.add_entry(app_src, { name: "json", value: json_new, is_platform: Bool.False }) == Err(Exists)

# R-H1: add_entry to the packages record of a platform header
expect {
	out = Header.add_entry(platform_src, { name: "parser", value: parser, is_platform: Bool.False }) ?? ""
	triples(out).contains(("parser", parser, Bool.False)) and outside(out) == outside(platform_src)
}

roc_line = "\troc: \"nightly-2026-10-09-258ab27\",\n"

json_line = "\t# JSON for the config file\n\tjson: \"${json}\",\n"

# Settled Q10 (many lines): the new entry is a new line after the last entry, with its indent and a comma
expect Header.add_entry(app_src, { name: "parser", value: parser, is_platform: Bool.False }) == Ok(app_src.replace_first(roc_line, "${roc_line}\tparser: \"${parser}\",\n"))

# Settled Q10 (one line): the new entry goes after the last entry, after `, `
expect Header.add_entry(pkg_src, { name: "json", value: json, is_platform: Bool.False }) == Ok(pkg_src.replace_first("\"${parser}\" }", "\"${parser}\", json: \"${json}\" }"))

# Settled Q10 (empty record): `{}` gives `{ name: "value" }`
expect Header.add_entry("app [main!] {}\n", { name: "json", value: json, is_platform: Bool.False }) == Ok("app [main!] { json: \"${json}\" }\n")

# Settled Q10: a platform entry is `name: platform "value"`
expect Header.add_entry("app [main!] { json: \"${json}\" }\n", { name: "pf", value: cli, is_platform: Bool.True }) == Ok("app [main!] { json: \"${json}\", pf: platform \"${cli}\" }\n")

# Settled Q10 (many lines): a comma is added after a last entry that has none
expect Header.add_entry("app [main!] {\n\tpf: platform \"${cli}\"\n}\n", { name: "json", value: json, is_platform: Bool.False }) == Ok("app [main!] {\n\tpf: platform \"${cli}\",\n\tjson: \"${json}\",\n}\n")

# Settled Q10 (many lines): the new line comes after a comment at the end of the line of the last entry
expect Header.add_entry("app [main!] {\n\tjson: \"${json}\", # note\n}\n", { name: "parser", value: parser, is_platform: Bool.False }) == Ok("app [main!] {\n\tjson: \"${json}\", # note\n\tparser: \"${parser}\",\n}\n")

# Settled Q10 (many lines): the indent of the last entry, in the packages record of a platform
expect Header.add_entry(platform_src, { name: "parser", value: parser, is_platform: Bool.False }) == Ok(platform_src.replace_first("\t\tjson: \"${json}\",\n", "\t\tjson: \"${json}\",\n\t\tparser: \"${parser}\",\n"))

# Settled Q11 (many lines): the whole line of the entry goes. The comment line above it stays.
expect Header.remove_entry(app_src, "json") == Ok(app_src.replace_first(json_line, "\t# JSON for the config file\n"))

# Settled Q11 (many lines): a comment at the end of the line goes with the line
expect Header.remove_entry("app [main!] {\n\tjson: \"${json}\", # note\n\tparser: \"${parser}\",\n}\n", "json") == Ok("app [main!] {\n\tparser: \"${parser}\",\n}\n")

# Settled Q11 (one line): the entry and one `, ` next to it go
expect {
	src = "app [main!] { a: \"x\", b: \"y\" }\n"
	Header.remove_entry(src, "a") == Ok("app [main!] { b: \"y\" }\n") and Header.remove_entry(src, "b") == Ok("app [main!] { a: \"x\" }\n")
}

# Settled Q11 (one line): the only entry goes, and `{}` stays
expect Header.remove_entry(pkg_src, "parser") == Ok(pkg_src.replace_first("{ parser: \"${parser}\" }", "{}"))

# Settled Q12: set_value does not escape. A value with ", \, $ or a line break is BadValue.
expect ["a\"b", "a\\b", "a\${b}", "a\nb"].all(|v| Header.set_value(app_src, "json", v) == Err(BadValue))

# Settled Q12: add_entry with a bad value is BadValue
expect Header.add_entry(app_src, { name: "parser", value: "x\"y", is_platform: Bool.False }) == Err(BadValue)

# Settled Q13: an escape in a value is not decoded
expect triples("app [main!] { a: \"x\\u(41)y\" }\n") == [("a", "x\\u(41)y", Bool.False)]

# R-H1: set_value keeps the text after the header byte for byte, also the line breaks at the end of the file
expect {
	src = "app [main!] { json: \"${json}\" }\n\nmain! = |_args| Ok({})\n\n"
	Header.set_value(src, "json", json_new) == Ok("app [main!] { json: \"${json_new}\" }\n\nmain! = |_args| Ok({})\n\n")
}
