app [main!] { pkg: "../package/main.roc" }

import pkg.Header

import "fixtures/seeds/unicode-4.2.0.main.roc.txt" as unicode_4_2_0_main : Str
import "fixtures/seeds/unicode-4.2.0.fmt.roc.txt" as unicode_4_2_0_fmt : Str
import "fixtures/seeds/unicode-4.2.0.deps.tsv" as unicode_4_2_0_deps : Str
import "fixtures/seeds/http-1.0.0.main.roc.txt" as http_1_0_0_main : Str
import "fixtures/seeds/http-1.0.0.fmt.roc.txt" as http_1_0_0_fmt : Str
import "fixtures/seeds/http-1.0.0.deps.tsv" as http_1_0_0_deps : Str
import "fixtures/seeds/path-4.0.0.main.roc.txt" as path_4_0_0_main : Str
import "fixtures/seeds/path-4.0.0.fmt.roc.txt" as path_4_0_0_fmt : Str
import "fixtures/seeds/path-4.0.0.deps.tsv" as path_4_0_0_deps : Str
import "fixtures/seeds/roc-parser-2.0.0.main.roc.txt" as roc_parser_2_0_0_main : Str
import "fixtures/seeds/roc-parser-2.0.0.fmt.roc.txt" as roc_parser_2_0_0_fmt : Str
import "fixtures/seeds/roc-parser-2.0.0.deps.tsv" as roc_parser_2_0_0_deps : Str
import "fixtures/seeds/roc-ansi-0.13.0.main.roc.txt" as roc_ansi_0_13_0_main : Str
import "fixtures/seeds/roc-ansi-0.13.0.fmt.roc.txt" as roc_ansi_0_13_0_fmt : Str
import "fixtures/seeds/roc-ansi-0.13.0.deps.tsv" as roc_ansi_0_13_0_deps : Str
import "fixtures/seeds/roc-random-0.9.2.main.roc.txt" as roc_random_0_9_2_main : Str
import "fixtures/seeds/roc-random-0.9.2.fmt.roc.txt" as roc_random_0_9_2_fmt : Str
import "fixtures/seeds/roc-random-0.9.2.deps.tsv" as roc_random_0_9_2_deps : Str
import "fixtures/seeds/basic-cli-0.25.0.main.roc.txt" as basic_cli_0_25_0_main : Str
import "fixtures/seeds/basic-cli-0.25.0.fmt.roc.txt" as basic_cli_0_25_0_fmt : Str
import "fixtures/seeds/basic-cli-0.25.0.deps.tsv" as basic_cli_0_25_0_deps : Str
import "fixtures/seeds/basic-cli-0.29.0.main.roc.txt" as basic_cli_0_29_0_main : Str
import "fixtures/seeds/basic-cli-0.29.0.fmt.roc.txt" as basic_cli_0_29_0_fmt : Str
import "fixtures/seeds/basic-cli-0.29.0.deps.tsv" as basic_cli_0_29_0_deps : Str
import "fixtures/seeds/basic-webserver-0.17.0.main.roc.txt" as basic_webserver_0_17_0_main : Str
import "fixtures/seeds/basic-webserver-0.17.0.fmt.roc.txt" as basic_webserver_0_17_0_fmt : Str
import "fixtures/seeds/basic-webserver-0.17.0.deps.tsv" as basic_webserver_0_17_0_deps : Str
import "fixtures/seeds/roc-ray-0.10.0.main.roc.txt" as roc_ray_0_10_0_main : Str
import "fixtures/seeds/roc-ray-0.10.0.fmt.roc.txt" as roc_ray_0_10_0_fmt : Str
import "fixtures/seeds/roc-ray-0.10.0.deps.tsv" as roc_ray_0_10_0_deps : Str
import "fixtures/seeds/template-zig-1.0.0.main.roc.txt" as template_zig_1_0_0_main : Str
import "fixtures/seeds/template-zig-1.0.0.fmt.roc.txt" as template_zig_1_0_0_fmt : Str
import "fixtures/seeds/template-zig-1.0.0.deps.tsv" as template_zig_1_0_0_deps : Str
import "fixtures/seeds/template-zig-x.main.roc.txt" as template_zig_x_main : Str
import "fixtures/seeds/template-zig-x.fmt.roc.txt" as template_zig_x_fmt : Str
import "fixtures/seeds/template-zig-x.deps.tsv" as template_zig_x_deps : Str
import "fixtures/seeds/roc-s2-geometry.main.roc.txt" as roc_s2_geometry_main : Str
import "fixtures/seeds/roc-s2-geometry.fmt.roc.txt" as roc_s2_geometry_fmt : Str
import "fixtures/seeds/roc-s2-geometry.deps.tsv" as roc_s2_geometry_deps : Str
import "fixtures/seeds/app-webserver.main.roc.txt" as app_webserver_main : Str
import "fixtures/seeds/app-webserver.fmt.roc.txt" as app_webserver_fmt : Str
import "fixtures/seeds/app-print.main.roc.txt" as app_print_main : Str
import "fixtures/seeds/app-print.fmt.roc.txt" as app_print_fmt : Str

main! = |_args| Ok({})

# Seeds: the main.roc files of packages in the roc package cache (Design 2.2), and 2 app files of the
# Talon repository. tests/fixtures/seeds/SOURCES.tsv has the source path and license of each.
# scripts/seeds.sh made the expected values with tools outside this package:
# the sidecar <hash>.deps.json that roc wrote (kind, and the deps with no roc: entry), and roc fmt.

## The kind as the sidecar writes it.
kind_name : Header -> Str
kind_name = |h| match h.kind() {
	App => "app"
	Package => "package"
	Platform(_) => "platform"
}

## The entries as (name, value, is_platform), in source order.
triples : Header -> List((Str, Str, Bool))
triples = |h| h.entries().map(|e| (e.name, e.value, e.is_platform))

## The bytes of a span as text.
slice : Str, { start : U64, end : U64 } -> Str
slice = |source, span| Str.from_utf8(source.to_utf8().sublist({ start: span.start, len: span.end - span.start })) ?? ""

## Reads a deps.tsv file of scripts/seeds.sh.
sidecar : Str -> { kind : Str, deps : List((Str, Str, Bool)) }
sidecar = |tsv| tsv.split_on("\n").fold(
	{ kind: "", deps: [] },
	|acc, line| match line.split_on("\t") {
		["kind", k] => { ..acc, kind: k }
		["dep", alias, spec, p] => { ..acc, deps: acc.deps.append((alias, spec, p == "true")) }
		_ => acc
	},
)

## The kind and the entries (not roc:) are the ones that roc wrote in the sidecar, in the same order.
matches_sidecar : Str, Str -> Bool
matches_sidecar = |source, tsv| match Header.parse(source) {
	Ok(h) => {
		want = sidecar(tsv)
		kind_name(h) == want.kind and triples(h).keep_if(|(n, _, _)| n != "roc") == want.deps
	}

	Err(_) => Bool.False
}

## roc fmt gives the same header. roc fmt sorts the lists and the entries and moves the roc: pin (R-H2),
## so the compare uses sets and leaves out the value of roc:.
same_after_fmt : Str, Str -> Bool
same_after_fmt = |source, formatted| match (Header.parse(source), Header.parse(formatted)) {
	(Ok(a), Ok(b)) => {
		no_pin = |h| Set.from_list(triples(h).map(|(n, v, p)| if n == "roc" (n, "", p) else (n, v, p)))
		a.kind() == b.kind() and Set.from_list(a.exposed()) == Set.from_list(b.exposed()) and no_pin(a) == no_pin(b)
	}

	_ => Bool.False
}

## Each span points at its text: the header starts with its keyword, an entry span starts with the
## name and ends with the closing quote, and a value span holds the value.
spans_point_at_text : Str -> Bool
spans_point_at_text = |source| match Header.parse(source) {
	Ok(h) => {
		keyword = match h.kind() {
			App => "app"
			Package => "package"
			Platform(_) => "platform"
		}
		entry_ok = |e| slice(source, e.value_span) == e.value and slice(source, e.span).starts_with(e.name) and slice(source, e.span).ends_with("\"")
		slice(source, h.span()).starts_with(keyword) and h.entries().all(entry_ok)
	}

	Err(_) => Bool.False
}

# R-PK5, Design 2.2 (seed unicode-4.2.0): kind and entries equal the roc sidecar
expect matches_sidecar(unicode_4_2_0_main, unicode_4_2_0_deps)

# R-PK5, R-GA7 (seed unicode-4.2.0): parse gives the same header after roc fmt
expect same_after_fmt(unicode_4_2_0_main, unicode_4_2_0_fmt)

# R-H1 (seed unicode-4.2.0): the spans point at their text
expect spans_point_at_text(unicode_4_2_0_main)

# R-PK5, Design 2.2 (seed http-1.0.0): kind and entries equal the roc sidecar
expect matches_sidecar(http_1_0_0_main, http_1_0_0_deps)

# R-PK5, R-GA7 (seed http-1.0.0): parse gives the same header after roc fmt
expect same_after_fmt(http_1_0_0_main, http_1_0_0_fmt)

# R-H1 (seed http-1.0.0): the spans point at their text
expect spans_point_at_text(http_1_0_0_main)

# R-PK5, Design 2.2 (seed path-4.0.0): kind and entries equal the roc sidecar
expect matches_sidecar(path_4_0_0_main, path_4_0_0_deps)

# R-PK5, R-GA7 (seed path-4.0.0): parse gives the same header after roc fmt
expect same_after_fmt(path_4_0_0_main, path_4_0_0_fmt)

# R-H1 (seed path-4.0.0): the spans point at their text
expect spans_point_at_text(path_4_0_0_main)

# R-PK5, Design 2.2 (seed roc-parser-2.0.0): kind and entries equal the roc sidecar
expect matches_sidecar(roc_parser_2_0_0_main, roc_parser_2_0_0_deps)

# R-PK5, R-GA7 (seed roc-parser-2.0.0): parse gives the same header after roc fmt
expect same_after_fmt(roc_parser_2_0_0_main, roc_parser_2_0_0_fmt)

# R-H1 (seed roc-parser-2.0.0): the spans point at their text
expect spans_point_at_text(roc_parser_2_0_0_main)

# R-PK5, Design 2.2 (seed roc-ansi-0.13.0): kind and entries equal the roc sidecar
expect matches_sidecar(roc_ansi_0_13_0_main, roc_ansi_0_13_0_deps)

# R-PK5, R-GA7 (seed roc-ansi-0.13.0): parse gives the same header after roc fmt
expect same_after_fmt(roc_ansi_0_13_0_main, roc_ansi_0_13_0_fmt)

# R-H1 (seed roc-ansi-0.13.0): the spans point at their text
expect spans_point_at_text(roc_ansi_0_13_0_main)

# R-PK5, Design 2.2 (seed roc-random-0.9.2): kind and entries equal the roc sidecar
expect matches_sidecar(roc_random_0_9_2_main, roc_random_0_9_2_deps)

# R-PK5, R-GA7 (seed roc-random-0.9.2): parse gives the same header after roc fmt
expect same_after_fmt(roc_random_0_9_2_main, roc_random_0_9_2_fmt)

# R-H1 (seed roc-random-0.9.2): the spans point at their text
expect spans_point_at_text(roc_random_0_9_2_main)

# R-PK5, Design 2.2 (seed basic-cli-0.25.0): kind and entries equal the roc sidecar
expect matches_sidecar(basic_cli_0_25_0_main, basic_cli_0_25_0_deps)

# R-PK5, R-GA7 (seed basic-cli-0.25.0): parse gives the same header after roc fmt
expect same_after_fmt(basic_cli_0_25_0_main, basic_cli_0_25_0_fmt)

# R-H1 (seed basic-cli-0.25.0): the spans point at their text
expect spans_point_at_text(basic_cli_0_25_0_main)

# R-PK5, Design 2.2 (seed basic-cli-0.29.0): kind and entries equal the roc sidecar
expect matches_sidecar(basic_cli_0_29_0_main, basic_cli_0_29_0_deps)

# R-PK5, R-GA7 (seed basic-cli-0.29.0): parse gives the same header after roc fmt
expect same_after_fmt(basic_cli_0_29_0_main, basic_cli_0_29_0_fmt)

# R-H1 (seed basic-cli-0.29.0): the spans point at their text
expect spans_point_at_text(basic_cli_0_29_0_main)

# R-PK5, Design 2.2 (seed basic-webserver-0.17.0): kind and entries equal the roc sidecar
expect matches_sidecar(basic_webserver_0_17_0_main, basic_webserver_0_17_0_deps)

# R-PK5, R-GA7 (seed basic-webserver-0.17.0): parse gives the same header after roc fmt
expect same_after_fmt(basic_webserver_0_17_0_main, basic_webserver_0_17_0_fmt)

# R-H1 (seed basic-webserver-0.17.0): the spans point at their text
expect spans_point_at_text(basic_webserver_0_17_0_main)

# R-PK5, Design 2.2 (seed roc-ray-0.10.0): kind and entries equal the roc sidecar
expect matches_sidecar(roc_ray_0_10_0_main, roc_ray_0_10_0_deps)

# R-PK5, R-GA7 (seed roc-ray-0.10.0): parse gives the same header after roc fmt
expect same_after_fmt(roc_ray_0_10_0_main, roc_ray_0_10_0_fmt)

# R-H1 (seed roc-ray-0.10.0): the spans point at their text
expect spans_point_at_text(roc_ray_0_10_0_main)

# R-PK5, Design 2.2 (seed template-zig-1.0.0): kind and entries equal the roc sidecar
expect matches_sidecar(template_zig_1_0_0_main, template_zig_1_0_0_deps)

# R-PK5, R-GA7 (seed template-zig-1.0.0): parse gives the same header after roc fmt
expect same_after_fmt(template_zig_1_0_0_main, template_zig_1_0_0_fmt)

# R-H1 (seed template-zig-1.0.0): the spans point at their text
expect spans_point_at_text(template_zig_1_0_0_main)

# R-PK5, Design 2.2 (seed template-zig-x): kind and entries equal the roc sidecar
expect matches_sidecar(template_zig_x_main, template_zig_x_deps)

# R-PK5, R-GA7 (seed template-zig-x): parse gives the same header after roc fmt
expect same_after_fmt(template_zig_x_main, template_zig_x_fmt)

# R-H1 (seed template-zig-x): the spans point at their text
expect spans_point_at_text(template_zig_x_main)

# R-PK5, Design 2.2 (seed roc-s2-geometry): kind and entries equal the roc sidecar
expect matches_sidecar(roc_s2_geometry_main, roc_s2_geometry_deps)

# R-PK5, R-GA7 (seed roc-s2-geometry): parse gives the same header after roc fmt
expect same_after_fmt(roc_s2_geometry_main, roc_s2_geometry_fmt)

# R-H1 (seed roc-s2-geometry): the spans point at their text
expect spans_point_at_text(roc_s2_geometry_main)

# R-PK5, R-GA7 (seed app-webserver): parse gives the same header after roc fmt
expect same_after_fmt(app_webserver_main, app_webserver_fmt)

# R-H1 (seed app-webserver): the spans point at their text
expect spans_point_at_text(app_webserver_main)

# R-PK5, R-GA7 (seed app-print): parse gives the same header after roc fmt
expect same_after_fmt(app_print_main, app_print_fmt)

# R-H1 (seed app-print): the spans point at their text
expect spans_point_at_text(app_print_main)
