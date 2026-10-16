## A package release URL: `https://<host>/<path>/<tag>/<hash>.tar.zst`.
##
## The version is the one `X.Y.Z` run of the URL. The text around the run is
## part of the group, so the tags `v1.2.0` and `1.2.0` give two groups.
##
## | Item | Rule |
## | --- | --- |
## | Where | The run is searched in all of the URL after the scheme, the host included. |
## | Dotted number | A longest text of digit groups with one `.` between them: no digit and no `.digit` next to it. `1.2.3.4` and `127.0.0.1` are one dotted number with 4 parts. |
## | Run | A dotted number with exactly 3 parts. A letter or `-` can touch it: `v1.9.0-rc2`, `1.2.3x`, `a.1.2.3`. |
## | Numbers | A part is read as a number: `01.2.3` is version 1.2.3. A part above the `U64` range makes the dotted number not a run. |
## | Hash | The text of the last path segment before `.tar.zst`. It must not be empty. Its characters are not checked. |
PackageUrl :: {
	text : Str,
	form : Str,
	major : U64,
	minor : U64,
	patch : U64,
	hash : Str,
}.{
	is_eq : _

	to_hash : _

	## Reads a release URL. When the URL has more than one fault, the error is
	## the first row that applies, in the order of this table.
	##
	## | Error | When |
	## | --- | --- |
	## | `BadScheme` | The text does not start with `https://` or `http://`. A path entry such as `../util/main.roc` gives this error. |
	## | `NoHash` | The last path segment is not `<hash>.tar.zst` with a hash that is not empty. |
	## | `NoVersion` | The URL has no `X.Y.Z` run. |
	## | `ManyVersions` | The URL has two or more `X.Y.Z` runs, also when one of them is `0.0.0`. |
	## | `ZeroVersion` | The run is `0.0.0`. |
	parse : Str -> Try(PackageUrl, [BadScheme, NoHash, NoVersion, ManyVersions, ZeroVersion])
	parse = |text| {
		rest = after_scheme(text)?
		{ hash, cut } = hash_segment(rest)?
		bytes = rest.to_utf8()
		run = match runs(bytes) {
			[] => return Err(NoVersion)
			[one] => one
			_ => return Err(ManyVersions)
		}
		if run.major == 0 and run.minor == 0 and run.patch == 0 {
			return Err(ZeroVersion)
		}
		Ok({ text, form: form_of(bytes, run, cut), major: run.major, minor: run.minor, patch: run.patch, hash })
	}

	## The URL text, as `parse` got it.
	to_str : PackageUrl -> Str
	to_str = |url| url.text

	## The three numbers of the `X.Y.Z` run.
	version : PackageUrl -> { major : U64, minor : U64, patch : U64 }
	version = |url| { major: url.major, minor: url.minor, patch: url.patch }

	## The text of the last path segment before `.tar.zst`.
	hash : PackageUrl -> Str
	hash = |url| url.hash

	## The URL with no scheme, `{v}` in place of the run, and no hash segment:
	## `github.com/roc-lang/unicode/releases/download/{v}/`.
	url_form : PackageUrl -> Str
	url_form = |url| url.form

	## The major (`4` for `4.2.0`), or `0.minor` below 1.0 (`0.25` for `0.25.1`).
	series : PackageUrl -> Str
	series = |url| if url.major >= 1 url.major.to_str() else "0.${url.minor.to_str()}"

	## The group key: the URL form and the series. Two URLs are the same
	## package to Roc when their groups are equal.
	group : PackageUrl -> { form : Str, series : Str }
	group = |url| { form: url.form, series: url.series() }
}

## A dotted number with 3 parts: its byte range in the text after the scheme, and its parts.
Run : { start : U64, end : U64, major : U64, minor : U64, patch : U64 }

## The text after `https://` or `http://`.
after_scheme : Str -> Try(Str, [BadScheme])
after_scheme = |text|
	if text.starts_with("https://") {
		Ok(text.drop_prefix("https://"))
	} else if text.starts_with("http://") {
		Ok(text.drop_prefix("http://"))
	} else {
		Err(BadScheme)
	}

## The hash of the last path segment `<hash>.tar.zst`, and the byte index after the last `/`.
hash_segment : Str -> Try({ hash : Str, cut : U64 }, [NoHash])
hash_segment = |rest| match rest.split_last("/") {
	Ok({ before, after }) if after.ends_with(".tar.zst") and after != ".tar.zst" =>
		Ok({ hash: after.drop_suffix(".tar.zst"), cut: before.count_utf8_bytes() + 1 })

	_ => Err(NoHash)
}

## The URL form: the text up to the hash segment, with `{v}` in place of the run.
form_of : List(U8), Run, U64 -> Str
form_of = |bytes, run, cut|
	if run.end <= cut {
		before = bytes.take_first(run.start)
		after = bytes.sublist({ start: run.end, len: cut - run.end })
		Str.from_utf8_lossy(before.concat("{v}".to_utf8()).concat(after))
	} else {
		# The run is in the hash segment, so the form has no `{v}`.
		Str.from_utf8_lossy(bytes.take_first(cut))
	}

is_digit : U8 -> Bool
is_digit = |b| b >= '0' and b <= '9'

## The byte at an index, or 0 after the end.
at : List(U8), U64 -> U8
at = |bytes, i| bytes.get(i) ?? 0

## The number with one more digit at its end.
push_digit : U64, U64 -> Try(U64, [Overflow])
push_digit = |value, digit| value.times_try(10)?.plus_try(digit)

## The value of the digit group at `start`, its end, and `Bool.False` when it is above the U64 range.
digits : List(U8), U64 -> { value : U64, end : U64, fits : Bool }
digits = |bytes, start| {
	var $i = start
	var $value = 0
	var $fits = Bool.True
	while is_digit(at(bytes, $i)) {
		digit = (at(bytes, $i) - '0').to_u64()
		match push_digit($value, digit) {
			Ok(v) => {
				$value = v
			}

			Err(_) => {
				$fits = Bool.False
			}
		}
		$i = $i + 1
	}
	{ value: $value, end: $i, fits: $fits }
}

## The longest dotted number at `start`: digit groups with one `.` between them.
dotted : List(U8), U64 -> { parts : List(U64), end : U64, fits : Bool }
dotted = |bytes, start| {
	first = digits(bytes, start)
	var $parts = [first.value]
	var $end = first.end
	var $fits = first.fits
	while at(bytes, $end) == '.' and is_digit(at(bytes, $end + 1)) {
		next = digits(bytes, $end + 1)
		$parts = $parts.append(next.value)
		$end = next.end
		$fits = $fits and next.fits
	}
	{ parts: $parts, end: $end, fits: $fits }
}

## Each dotted number with exactly 3 parts that are all in the U64 range.
runs : List(U8) -> List(Run)
runs = |bytes| {
	var $found = []
	var $i = 0
	while $i < bytes.len() {
		if is_digit(at(bytes, $i)) {
			number = dotted(bytes, $i)
			match number.parts {
				[major, minor, patch] if number.fits => {
					$found = $found.append({ start: $i, end: number.end, major, minor, patch })
				}

				_ => {}
			}
			$i = number.end
		} else {
			$i = $i + 1
		}
	}
	$found
}
