app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Header
import "../tests/fixtures/seeds/unicode-4.2.0.main.roc.txt" as unicode_4_2_0_main : Str
import "../tests/fixtures/seeds/unicode-4.2.0.fmt.roc.txt" as unicode_4_2_0_fmt : Str
import "../tests/fixtures/seeds/http-1.0.0.main.roc.txt" as http_1_0_0_main : Str
import "../tests/fixtures/seeds/http-1.0.0.fmt.roc.txt" as http_1_0_0_fmt : Str
import "../tests/fixtures/seeds/path-4.0.0.main.roc.txt" as path_4_0_0_main : Str
import "../tests/fixtures/seeds/path-4.0.0.fmt.roc.txt" as path_4_0_0_fmt : Str
import "../tests/fixtures/seeds/roc-parser-2.0.0.main.roc.txt" as roc_parser_2_0_0_main : Str
import "../tests/fixtures/seeds/roc-parser-2.0.0.fmt.roc.txt" as roc_parser_2_0_0_fmt : Str
import "../tests/fixtures/seeds/roc-ansi-0.13.0.main.roc.txt" as roc_ansi_0_13_0_main : Str
import "../tests/fixtures/seeds/roc-ansi-0.13.0.fmt.roc.txt" as roc_ansi_0_13_0_fmt : Str
import "../tests/fixtures/seeds/roc-random-0.9.2.main.roc.txt" as roc_random_0_9_2_main : Str
import "../tests/fixtures/seeds/roc-random-0.9.2.fmt.roc.txt" as roc_random_0_9_2_fmt : Str
import "../tests/fixtures/seeds/basic-cli-0.25.0.main.roc.txt" as basic_cli_0_25_0_main : Str
import "../tests/fixtures/seeds/basic-cli-0.25.0.fmt.roc.txt" as basic_cli_0_25_0_fmt : Str
import "../tests/fixtures/seeds/basic-cli-0.29.0.main.roc.txt" as basic_cli_0_29_0_main : Str
import "../tests/fixtures/seeds/basic-cli-0.29.0.fmt.roc.txt" as basic_cli_0_29_0_fmt : Str
import "../tests/fixtures/seeds/basic-webserver-0.17.0.main.roc.txt" as basic_webserver_0_17_0_main : Str
import "../tests/fixtures/seeds/basic-webserver-0.17.0.fmt.roc.txt" as basic_webserver_0_17_0_fmt : Str
import "../tests/fixtures/seeds/roc-ray-0.10.0.main.roc.txt" as roc_ray_0_10_0_main : Str
import "../tests/fixtures/seeds/roc-ray-0.10.0.fmt.roc.txt" as roc_ray_0_10_0_fmt : Str
import "../tests/fixtures/seeds/template-zig-1.0.0.main.roc.txt" as template_zig_1_0_0_main : Str
import "../tests/fixtures/seeds/template-zig-1.0.0.fmt.roc.txt" as template_zig_1_0_0_fmt : Str
import "../tests/fixtures/seeds/template-zig-x.main.roc.txt" as template_zig_x_main : Str
import "../tests/fixtures/seeds/template-zig-x.fmt.roc.txt" as template_zig_x_fmt : Str
import "../tests/fixtures/seeds/roc-s2-geometry.main.roc.txt" as roc_s2_geometry_main : Str
import "../tests/fixtures/seeds/roc-s2-geometry.fmt.roc.txt" as roc_s2_geometry_fmt : Str
import "../tests/fixtures/seeds/app-webserver.main.roc.txt" as app_webserver_main : Str
import "../tests/fixtures/seeds/app-webserver.fmt.roc.txt" as app_webserver_fmt : Str
import "../tests/fixtures/seeds/app-print.main.roc.txt" as app_print_main : Str
import "../tests/fixtures/seeds/app-print.fmt.roc.txt" as app_print_fmt : Str

# TESTING.md 4 ("parse after print gives the same value"), R-H1, R-RV1: parse after an edit
# (set_value, remove_entry, add_entry) on a seed gives the edited value. The kind and the list
# do not change, and the other entries keep their order.

## Each seed file (Design 2.2 cache) and its roc fmt form.
seeds : List(Str)
seeds = [
	unicode_4_2_0_main,
	unicode_4_2_0_fmt,
	http_1_0_0_main,
	http_1_0_0_fmt,
	path_4_0_0_main,
	path_4_0_0_fmt,
	roc_parser_2_0_0_main,
	roc_parser_2_0_0_fmt,
	roc_ansi_0_13_0_main,
	roc_ansi_0_13_0_fmt,
	roc_random_0_9_2_main,
	roc_random_0_9_2_fmt,
	basic_cli_0_25_0_main,
	basic_cli_0_25_0_fmt,
	basic_cli_0_29_0_main,
	basic_cli_0_29_0_fmt,
	basic_webserver_0_17_0_main,
	basic_webserver_0_17_0_fmt,
	roc_ray_0_10_0_main,
	roc_ray_0_10_0_fmt,
	template_zig_1_0_0_main,
	template_zig_1_0_0_fmt,
	template_zig_x_main,
	template_zig_x_fmt,
	roc_s2_geometry_main,
	roc_s2_geometry_fmt,
	app_webserver_main,
	app_webserver_fmt,
	app_print_main,
	app_print_fmt,
]

value_chars : List(U8)
value_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:/._-".to_utf8()

name_chars : List(U8)
name_chars = "abcdefghijklmnopqrstuvwxyz".to_utf8()

## Text from indexes into a character table.
chars : List(U8), List(U8) -> Str
chars = |table, picks| Str.from_utf8(picks.map(|p| table.get(p.to_u64() % table.len()) ?? 'x')) ?? "x"

Input := { seed : U64, entry : U64, op : U8, value : List(U8), name : List(U8) }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { seed: Fuzz.u64, entry: Fuzz.u64, op: Fuzz.u8_in(0, 2), value: Fuzz.list(Fuzz.u8, 100), name: Fuzz.list(Fuzz.u8, 8) }.Fuzz
}

source_of : Input -> Str
source_of = |input| seeds.get(input.seed % seeds.len()) ?? ""

value_of : Input -> Str
value_of = |input| chars(value_chars, input.value)

name_of : Input -> Str
name_of = |input| if input.name.is_empty() "x" else chars(name_chars, input.name)

## The bytes of a span as text.
slice : Str, { start : U64, end : U64 } -> Str
slice = |source, span| Str.from_utf8_lossy(source.to_utf8().sublist({ start: span.start, len: span.end - span.start }))

## The entries as (name, value, is_platform), in source order.
triples : Header -> List((Str, Str, Bool))
triples = |h| h.entries().map(|e| (e.name, e.value, e.is_platform))

show : Input -> Str
show = |input| "seed ${(input.seed % seeds.len()).to_str()}, entry ${input.entry.to_str()}, op ${input.op.to_str()}, value ${Str.inspect(value_of(input))}, name ${Str.inspect(name_of(input))}"

## The list with the item at index `k` replaced, or removed.
replace_at : List(a), U64, a -> List(a)
replace_at = |list, k, item| list.take_first(k).append(item).concat(list.drop_first(k + 1))

remove_at : List(a), U64 -> List(a)
remove_at = |list, k| list.take_first(k).concat(list.drop_first(k + 1))

test : Input -> Fuzz.Outcome
test = |input| {
	source = source_of(input)
	header = match Header.parse(source) {
		Ok(h) => h
		Err(_) => crash "a seed did not parse"
	}
	old = triples(header)
	k = if old.is_empty() 0 else input.entry % old.len()
	name = (old.get(k) ?? ("", "", Bool.False)).0
	value = value_of(input)
	edited = match input.op {
		0 if !old.is_empty() => Header.set_value(source, name, value).map_ok(|out| (out, |t| t == replace_at(old, k, (name, value, (old.get(k) ?? ("", "", Bool.False)).2))))
		1 if !old.is_empty() => Header.remove_entry(source, name).map_ok(|out| (out, |t| t == remove_at(old, k)))
		2 => {
			new = name_of(input)
			if old.any(|(n, _, _)| n == new) {
				return if Header.add_entry(source, { name: new, value, is_platform: Bool.False }) == Err(Exists) Fuzz.keep else crash "add_entry of a name in the header did not give Exists"
			}
			Header.add_entry(source, { name: new, value, is_platform: Bool.False }).map_ok(|out| (out, |t| t.keep_if(|(n, _, _)| n != new) == old and t.contains((new, value, Bool.False))))
		}

		_ => return Fuzz.reject
	}
	match edited {
		Ok((out, good)) =>
			match Header.parse(out) {
				Ok(h) if h.kind() == header.kind() and h.exposed() == header.exposed() and good(triples(h)) => Fuzz.keep
				Ok(_) => crash "parse after the edit gave another value"
				Err(_) => crash "the edit gave a header that does not parse"
			}

		Err(_) => crash "the edit failed"
	}
}

target = Fuzz.target_with({
	name: "header-edit-reparse",
	generator: Input.generator_for(Default),
	test,
	show,
})
