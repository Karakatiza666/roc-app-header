app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Header
import pkg.Imports
import "../tests/fixtures/seeds/basic-cli-0.25.0.main.roc.txt" as basic_cli : Str
import "../tests/fixtures/seeds/basic-webserver-0.17.0.main.roc.txt" as basic_webserver : Str
import "../tests/fixtures/seeds/roc-parser-2.0.0.main.roc.txt" as roc_parser : Str
import "../tests/fixtures/seeds/template-zig-1.0.0.main.roc.txt" as template_zig : Str
import "../tests/fixtures/seeds/path-4.0.0.main.roc.txt" as path : Str
import "../tests/fixtures/seeds/app-webserver.main.roc.txt" as app_webserver : Str

# TESTING.md 4, R-PK5: Header.parse and Imports.scan never crash, on any text.
# The text is a seed header (Design 2.2 cache) with a cut and an insert, or any text.

seeds : List(Str)
seeds = [basic_cli, basic_webserver, roc_parser, template_zig, path, app_webserver]

Input := { seed : U64, cut : U64, drop : U64, insert : Str, raw : Bool }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { seed: Fuzz.u64, cut: Fuzz.u64, drop: Fuzz.u64_in(0, 40), insert: Fuzz.str, raw: Fuzz.map(Fuzz.u8_in(0, 3), |b| b == 0) }.Fuzz
}

## The seed with `drop` bytes at `cut` replaced by `insert`. The bytes go back to text with
## the lossy decode, so a cut in a UTF-8 sequence still gives text.
text_of : Input -> Str
text_of = |input| {
	if input.raw {
		return input.insert
	}
	bytes = (seeds.get(input.seed % seeds.len()) ?? "").to_utf8()
	at = input.cut % (bytes.len() + 1)
	mixed = bytes.take_first(at).concat(input.insert.to_utf8()).concat(bytes.drop_first(at + input.drop))
	Str.from_utf8_lossy(mixed)
}

test : Input -> Fuzz.Outcome
test = |input| {
	text = text_of(input)
	n_entries = match Header.parse(text) {
		Ok(h) => h.entries().len()
		Err(_) => 0
	}
	n_imports = Imports.scan(text).len()
	if n_entries + n_imports >= 0 Fuzz.keep else crash "unreachable"
}

target = Fuzz.target_with({
	name: "header-total",
	generator: Input.generator_for(Default),
	test,
	show: |input| Str.inspect(text_of(input)),
})
