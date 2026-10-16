app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.PackageUrl

# TESTING.md 4 (MVS and group key), Design 2 (group key), R-ID1, R-ID2, R-DI5: PackageUrl.parse of a
# URL made from known parts gives the parts back. The oracle below is written from the rule
# text only: the group is the URL minus the scheme, minus the one X.Y.Z run, minus the hash,
# plus the series (the major, or 0.minor below 1.0). No run, two runs and 0.0.0 are errors.
#
# The words have no digit and no dot, and the text after the run starts with `-`, so the
# URL has no other run and no run touches a digit or a dot (the design does not say what
# `1.2.3.4` or `1.2.3x` give: a question in the slice file).

hosts : List(Str)
hosts = ["github.com", "example.org", "codeberg.org", "localhost:8000"]

letters : List(U8)
letters = "abcdefghijklmnopqrstuvwxyz".to_utf8()

word_chars : List(U8)
word_chars = "abcdefghijklmnopqrstuvwxyz-".to_utf8()

base58 : List(U8)
base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".to_utf8()

## Text from indexes into a character table.
chars : List(U8), List(U8) -> Str
chars = |table, picks| Str.from_utf8(picks.map(|p| table.get(p.to_u64() % table.len()) ?? 'a')) ?? "a"

## A path segment with no digit and no dot. Never empty.
word : List(U8) -> Str
word = |picks| if picks.is_empty() "a" else chars(word_chars, picks)

Input := {
	scheme : U8,
	host : U8,
	segs : List(List(U8)),
	prefix : List(U8),
	dash : Bool,
	suffix : List(U8),
	extra : List(List(U8)),
	major : U64,
	minor : U64,
	patch : U64,
	mode : U8,
	hash : List(U8),
}.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		scheme: Fuzz.u8,
		host: Fuzz.u8,
		segs: Fuzz.list(Fuzz.list(Fuzz.u8, 8), 4),
		prefix: Fuzz.list(Fuzz.u8, 5),
		dash: Fuzz.map(Fuzz.u8, |b| b % 2 == 0),
		suffix: Fuzz.list(Fuzz.u8, 5),
		extra: Fuzz.list(Fuzz.list(Fuzz.u8, 6), 2),
		major: Fuzz.u64_in(0, 40),
		minor: Fuzz.u64_in(0, 40),
		patch: Fuzz.u64_in(0, 40),
		mode: Fuzz.u8_in(0, 3),
		hash: Fuzz.list(Fuzz.u8, 44),
	}.Fuzz
}

## The URL, and what the rule says that parse gives for it.
Case : {
	url : Str,
	want : [Good({ version : { major : U64, minor : U64, patch : U64 }, hash : Str, form : Str, series : Str }), NoVersion, ManyVersions, ZeroVersion],
}

make : Input -> Case
make = |input| {
	scheme = if input.scheme % 2 == 0 "https://" else "http://"
	host = hosts.get(input.host.to_u64() % hosts.len()) ?? "github.com"
	segs = input.segs.map(word)
	extra = input.extra.map(word)
	prefix = "${chars(letters, input.prefix)}${if input.dash "-" else ""}"
	suffix = if input.suffix.is_empty() "" else "-${chars(letters, input.suffix)}"
	# Always 44 characters, the length of most base58 BLAKE3 hashes (Design 2).
	hash = chars(base58, input.hash.concat(List.repeat(57, 44)).take_first(44))
	join = |parts| Str.join_with(parts, "/")
	url_of = |tag, before| "${scheme}${host}/${join(before.concat([tag]).concat(extra))}/${hash}.tar.zst"
	v = { major: input.major, minor: input.minor, patch: input.patch }
	run = "${v.major.to_str()}.${v.minor.to_str()}.${v.patch.to_str()}"
	match input.mode {
		2 => {
			tag = if "${prefix}${suffix}".is_empty() "latest" else "${prefix}${suffix}"
			{ url: url_of(tag, segs), want: NoVersion }
		}

		3 => {
			# A second run, as a whole segment before the tag. Not 0.0.0, so that only one rule applies.
			second = if v == { major: 0, minor: 0, patch: 0 } "${prefix}0.0.1${suffix}" else "${prefix}${run}${suffix}"
			{ url: url_of(second, segs.append("1.0.0")), want: ManyVersions }
		}

		_ =>
			if v == { major: 0, minor: 0, patch: 0 } {
				{ url: url_of("${prefix}${run}${suffix}", segs), want: ZeroVersion }
			} else {
				form = "${host}/${join(segs.concat(["${prefix}{v}${suffix}"]).concat(extra))}/"
				series = if v.major >= 1 v.major.to_str() else "0.${v.minor.to_str()}"
				{ url: url_of("${prefix}${run}${suffix}", segs), want: Good({ version: v, hash, form, series }) }
			}
	}
}

test : Input -> Fuzz.Outcome
test = |input| {
	case = make(input)
	agrees = match (case.want, PackageUrl.parse(case.url)) {
		(Good(w), Ok(u)) =>
			[
				u.to_str() == case.url,
				u.version() == w.version,
				u.hash() == w.hash,
				u.url_form() == w.form,
				u.series() == w.series,
				u.group() == { form: w.form, series: w.series },
			].all(|ok| ok)

		(NoVersion, Err(NoVersion)) => Bool.True
		(ManyVersions, Err(ManyVersions)) => Bool.True
		(ZeroVersion, Err(ZeroVersion)) => Bool.True
		_ => Bool.False
	}
	if agrees Fuzz.keep else crash "PackageUrl.parse disagrees with the group rule"
}

target = Fuzz.target_with({
	name: "group-key",
	generator: Input.generator_for(Default),
	test,
	show: |input| Str.inspect(make(input)),
})
