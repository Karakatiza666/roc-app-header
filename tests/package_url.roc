app [main!] { pkg: "../package/main.roc" }

import pkg.PackageUrl

main! = |_args| Ok({})

## Parse a URL that a test knows to be good.
url : Str -> PackageUrl
url = |text| match PackageUrl.parse(text) {
	Ok(u) => u
	Err(_) => crash "test URL did not parse: ${text}"
}

unicode_4_2_0 = "https://github.com/roc-lang/unicode/releases/download/4.2.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst"

basic_cli_0_25_0 = "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst"

http_1_0_0 = "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst"

hash_a = "4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w"

hash_b = "6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS"

## The URL of the repo `o/r` with the given tag and hash.
gh : Str, Str -> Str
gh = |tag, hash| "https://github.com/o/r/releases/download/${tag}/${hash}.tar.zst"

# R-ID2, Design 2 (hash form): version, hash and URL form of a real release URL
expect {
	u = url(unicode_4_2_0)
	[u.version() == { major: 4, minor: 2, patch: 0 }, u.hash() == hash_a, u.url_form() == "github.com/roc-lang/unicode/releases/download/{v}/"].all(|ok| ok)
}

# R-ID1: 4.2.0 is in series 4
expect url(unicode_4_2_0).series() == "4"

# R-ID1: 0.25.1 is in series 0.25 (below 1.0, 0.minor)
expect url(gh("0.25.1", hash_a)).series() == "0.25"

# R-ID1: 1.0.0 is in series 1
expect url(http_1_0_0).series() == "1"

# R-ID1: 0.0.5 is below 1.0, so its series is 0.minor = 0.0
expect url(gh("0.0.5", hash_a)).series() == "0.0"

# R-ID2: the group is the URL form plus the series
expect url(basic_cli_0_25_0).group() == { form: "github.com/roc-lang/basic-cli/releases/download/{v}/", series: "0.25" }

# Design 2 (group key): the run can be part of a segment, as in the tag v1.9.0-rc2. The tag text around it stays in the URL form.
expect {
	u = url(gh("v1.9.0-rc2", hash_a))
	u.version() == { major: 1, minor: 9, patch: 0 } and u.url_form() == "github.com/o/r/releases/download/v{v}-rc2/"
}

# R-DI5: the tags v1.2.0 and 1.2.0 give two groups
expect url(gh("v1.2.0", hash_a)).group() != url(gh("1.2.0", hash_a)).group()

# R-DI5: the tag 0.26.0-rc1 is not in the group of 0.26.0
expect url(gh("0.26.0-rc1", hash_a)).group() != url(gh("0.26.0", hash_a)).group()

# R-ID1, R-ID2: 4.2.0 and 4.3.1 are in one group (same URL form, series 4)
expect url(gh("4.2.0", hash_a)).group() == url(gh("4.3.1", hash_a)).group()

# R-ID1: 4.2.0 and 5.0.0 are two groups (series 4 and 5)
expect url(gh("4.2.0", hash_a)).group() != url(gh("5.0.0", hash_a)).group()

# R-ID1: 0.25.0 and 0.26.0 are two groups (series 0.25 and 0.26)
expect url(gh("0.25.0", hash_a)).group() != url(gh("0.26.0", hash_a)).group()

# R-ID1: 0.25.0 and 0.25.3 are in one group (series 0.25)
expect url(gh("0.25.0", hash_a)).group() == url(gh("0.25.3", hash_a)).group()

# Design 2 (group key): the host is part of the group
expect url("https://github.com/o/r/releases/download/1.0.0/${hash_a}.tar.zst").group() != url("https://example.com/o/r/releases/download/1.0.0/${hash_a}.tar.zst").group()

# Design 2 (group key): the scheme is not part of the group
expect url("http://127.0.0.1/o/1.0.0/${hash_a}.tar.zst").group() == url("https://127.0.0.1/o/1.0.0/${hash_a}.tar.zst").group()

# Design 2 (group key, "Conflicting Package Contents"): the hash is not part of the group or the version
expect {
	a = url(gh("1.0.0", hash_a))
	b = url(gh("1.0.0", hash_b))
	a.group() == b.group() and a.version() == b.version() and a.hash() != b.hash()
}

# Design 2 (group key): the run can be in a segment before the last one. Only the hash segment goes.
expect url("https://example.com/pkgs/1.2.3/linux/${hash_a}.tar.zst").url_form() == "example.com/pkgs/{v}/linux/"

# research/roc-http-fetch (roc fetched this URL, R-FE8): a loopback host with a port, version 1.0.0
expect {
	u = url("http://127.0.0.1:18765/1.0.0/${hash_a}.tar.zst")
	u.version() == { major: 1, minor: 0, patch: 0 } and u.url_form() == "127.0.0.1:18765/{v}/"
}

# research/roc-http-fetch, R-DI5: the tag prefix greet- stays in the group
expect url("http://127.0.0.1:18765/greet-1.0.0/${hash_a}.tar.zst").url_form() == "127.0.0.1:18765/greet-{v}/"

# R-DI5: a URL with no X.Y.Z run is not a release URL
expect PackageUrl.parse(gh("latest", hash_a)) == Err(NoVersion)

# R-DI5: a real URL with no run (the tag x of roc-platform-template-zig, seed ABFgWwu8...)
expect PackageUrl.parse("https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/x/ABFgWwu8SwPJfp7tzxDoTL41b1jFeHEac3RxUFSt1WWp.tar.zst") == Err(NoVersion)

# R-DI5: a URL with two runs is not a release URL
expect PackageUrl.parse("https://github.com/o/r-1.0.0/releases/download/2.0.0/${hash_a}.tar.zst") == Err(ManyVersions)

# R-DI5: the run 0.0.0 is not a release URL
expect PackageUrl.parse(gh("0.0.0", hash_a)) == Err(ZeroVersion)

# R-H3, Design 2 (entry form): a URL with no <hash>.tar.zst segment is not a release URL
expect PackageUrl.parse("https://github.com/o/r/archive/refs/tags/1.0.0/source.zip") == Err(NoHash)

# R-FE8: a scheme that roc does not fetch
expect PackageUrl.parse("ftp://example.com/o/1.0.0/${hash_a}.tar.zst") == Err(BadScheme)

# R-H7: a path entry is not a URL
expect PackageUrl.parse("../util/main.roc") == Err(BadScheme)

# R-H1: to_str gives the input text back, so an edit can write the text that it read
expect url(basic_cli_0_25_0).to_str() == basic_cli_0_25_0

# Settled Q5 (dotted number): 1.2.3.4 is one dotted number with 4 parts, so it is not a run
expect PackageUrl.parse(gh("1.2.3.4", hash_a)) == Err(NoVersion)

# Settled Q5 (run): a letter can touch the end of the run, and the letter stays in the URL form
expect {
	u = url(gh("1.2.3x", hash_a))
	u.version() == { major: 1, minor: 2, patch: 3 } and u.url_form() == "github.com/o/r/releases/download/{v}x/"
}

# Settled Q5 (run): a dot after a letter can touch the start of the run
expect {
	u = url(gh("a.1.2.3", hash_a))
	u.version() == { major: 1, minor: 2, patch: 3 } and u.url_form() == "github.com/o/r/releases/download/a.{v}/"
}

# Settled Q5 (numbers): a part is read as a number, so 01.2.3 is version 1.2.3
expect url(gh("01.2.3", hash_a)).version() == { major: 1, minor: 2, patch: 3 }

# Settled Q5 (numbers): a part above the U64 range makes the dotted number not a run
expect PackageUrl.parse(gh("18446744073709551616.0.0", hash_a)) == Err(NoVersion)

# Settled Q6 (where): the host is searched for the run too
expect {
	u = url("https://1.2.3.example.com/o/${hash_a}.tar.zst")
	u.version() == { major: 1, minor: 2, patch: 3 } and u.url_form() == "{v}.example.com/o/"
}

# Settled Q6 (dotted number): the loopback host 127.0.0.1 has 4 parts, so it is not a run
expect PackageUrl.parse("http://127.0.0.1:18765/x/${hash_a}.tar.zst") == Err(NoVersion)

# Settled Q8 (error order): no scheme and no hash gives BadScheme
expect PackageUrl.parse("example.com/latest/source.zip") == Err(BadScheme)

# Settled Q8 (error order): no hash and no run gives NoHash
expect PackageUrl.parse("https://example.com/latest/source.zip") == Err(NoHash)

# Settled Q8 (error order): two runs, one of them 0.0.0, gives ManyVersions
expect PackageUrl.parse("https://github.com/o/r-0.0.0/releases/download/1.0.0/${hash_a}.tar.zst") == Err(ManyVersions)

# Settled Q9 (hash): an empty hash is NoHash
expect PackageUrl.parse("https://example.com/1.0.0/.tar.zst") == Err(NoHash)
