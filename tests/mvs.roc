app [main!] { pkg: "../package/main.roc" }

import pkg.Mvs
import pkg.PackageUrl

main! = |_args| Ok({})

## Parse a URL that a test knows to be good.
url : Str -> PackageUrl
url = |text| match PackageUrl.parse(text) {
	Ok(u) => u
	Err(_) => crash "test URL did not parse: ${text}"
}

## The release URL of package `name` at `version`, with a fixed hash for each name and version.
rel : Str, Str -> Str
rel = |name, version| "https://github.com/o/${name}/releases/download/${version}/${hash_of(name, version)}.tar.zst"

## A base58 text of 44 characters, different for each name and version.
hash_of : Str, Str -> Str
hash_of = |name, version| {
	alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".to_utf8()
	seed = "${name}@${version}".to_utf8().fold(7, |acc, b| (acc * 31 + b.to_u64()) % 1000003)
	var $chars = []
	for i in 0.U64..<44 {
		$chars = $chars.append(alphabet.get((seed + i * 13) % 58) ?? '1')
	}
	Str.from_utf8($chars) ?? "bad"
}

## A non-platform edge.
dep : Str -> { url : PackageUrl, is_platform : Bool }
dep = |text| { url: url(text), is_platform: Bool.False }

## A platform edge.
pf : Str -> { url : PackageUrl, is_platform : Bool }
pf = |text| { url: url(text), is_platform: Bool.True }

## A deps function from a table of (URL text, dependency record).
graph : List((Str, List({ url : PackageUrl, is_platform : Bool }))) -> (PackageUrl -> List({ url : PackageUrl, is_platform : Bool }))
graph = |rows| |u| rows.find_first(|(text, _)| text == u.to_str()).map_ok(|(_, deps)| deps) ?? []

## The selection as a set of URL texts, so that the order does not count. Err when a URL is in it twice.
selected : List({ url : PackageUrl, is_platform : Bool }), (PackageUrl -> List({ url : PackageUrl, is_platform : Bool })) -> Try(Set(Str), [Failed])
selected = |root, deps| match Mvs.select(root, deps) {
	Ok(urls) => {
		texts = Set.from_list(urls.map(|u| u.to_str()))
		# One URL for each group: no URL twice.
		if texts.len() == urls.len() Ok(texts) else Err(Failed)
	}

	Err(_) => Err(Failed)
}

# Design 2 (MVS): with no root edges, nothing is selected
expect Mvs.select([], |_| []) == Ok([])

# Design 2 (MVS): in each group, the highest version that any edge names wins for the whole graph
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.2.0"))]), (rel("b", "1.0.0"), [dep(rel("c", "1.3.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel("c", "1.3.0")]))
}

# Design 2 (MVS): only the winner's deps are followed. c 1.0.0 loses, so its dep d is not in the build.
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([
		(rel("a", "1.0.0"), [dep(rel("c", "1.0.0"))]),
		(rel("b", "1.0.0"), [dep(rel("c", "1.1.0"))]),
		(rel("c", "1.0.0"), [dep(rel("d", "1.5.0"))]),
	])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel("c", "1.1.0")]))
}

# Design 2 (MVS): a raise found deep in the graph wins over a lower edge near the root
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("x", "1.0.0"))]
	deps = graph([
		(rel("a", "1.0.0"), [dep(rel("b", "1.0.0"))]),
		(rel("x", "1.0.0"), [dep(rel("y", "1.0.0"))]),
		(rel("y", "1.0.0"), [dep(rel("b", "1.4.0"))]),
	])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("x", "1.0.0"), rel("y", "1.0.0"), rel("b", "1.4.0")]))
}

# R-ID1, R-ID2: 1.2.0 and 2.0.0 are two groups, so both are in the build
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.2.0"))]), (rel("b", "1.0.0"), [dep(rel("c", "2.0.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel("c", "1.2.0"), rel("c", "2.0.0")]))
}

# R-ID1: below 1.0 the minor acts as the major. 0.3.0 and 0.4.0 are two groups.
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "0.3.0"))]), (rel("b", "1.0.0"), [dep(rel("c", "0.4.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel("c", "0.3.0"), rel("c", "0.4.0")]))
}

# R-ID1, Design 2 (MVS): 0.3.0 and 0.3.5 are one group, and 0.3.5 wins
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "0.3.0"))]), (rel("b", "1.0.0"), [dep(rel("c", "0.3.5"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel("c", "0.3.5")]))
}

# Design 2 (MVS, numbers compare as numbers): 1.10.0 is higher than 1.9.0
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.9.0"))]), (rel("b", "1.0.0"), [dep(rel("c", "1.10.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel("c", "1.10.0")]))
}

# Design 2 (app pin higher): an app pin that is higher than a dependency needs wins silently
expect {
	root = [pf(rel("basic-cli", "0.25.0")), dep(rel("http", "1.9.0"))]
	deps = graph([(rel("basic-cli", "0.25.0"), [dep(rel("http", "1.0.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("basic-cli", "0.25.0"), rel("http", "1.9.0")]))
}

# Design 2 (app pin lower, "Package Version Conflict"): an app pin that is lower than a dependency needs fails
expect {
	root = [dep(rel("http", "1.0.0")), dep(rel("json", "1.0.0"))]
	deps = graph([(rel("json", "1.0.0"), [dep(rel("http", "1.9.0"))])])
	match Mvs.select(root, deps) {
		Err(VersionConflict(conflicts)) =>
			conflicts.map(|c| (c.pinned.to_str(), c.needed.to_str(), c.by.to_str())) == [(rel("http", "1.0.0"), rel("http", "1.9.0"), rel("json", "1.0.0"))]

		_ => Bool.False
	}
}

# Design 2 (app pin): an app pin equal to what a dependency needs is not a conflict
expect {
	root = [dep(rel("c", "1.2.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.2.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("c", "1.2.0")]))
}

# Design 2 ("Conflicting Package Contents"): the winning group and version with two hashes fails
expect {
	other = "https://github.com/o/c/releases/download/1.0.0/${hash_of("other", "x")}.tar.zst"
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.0.0"))]), (rel("b", "1.0.0"), [dep(other)])])
	match Mvs.select(root, deps) {
		Err(ContentConflict(urls)) => Set.from_list(urls.map(|u| u.to_str())) == Set.from_list([rel("c", "1.0.0"), other])
		_ => Bool.False
	}
}

# Design 2 (one hash, many labels): http 1.0.0 and 2.0.0 with one hash are two groups, both in the build
expect {
	same = hash_of("http", "1.0.0")
	h1 = "https://github.com/o/http/releases/download/1.0.0/${same}.tar.zst"
	h2 = "https://github.com/o/http/releases/download/2.0.0/${same}.tar.zst"
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(h1)]), (rel("b", "1.0.0"), [dep(h2)])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), h1, h2]))
}

# Design 2 (platforms): the dependencies of the platform join version selection
expect {
	root = [pf(rel("basic-cli", "0.25.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("basic-cli", "0.25.0"), [dep(rel("http", "1.0.0"))]), (rel("a", "1.0.0"), [dep(rel("http", "1.2.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("basic-cli", "0.25.0"), rel("a", "1.0.0"), rel("http", "1.2.0")]))
}

# Design 2 (platforms): a package that names the same platform release is accepted
expect {
	root = [pf(rel("basic-cli", "0.25.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [pf(rel("basic-cli", "0.25.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("basic-cli", "0.25.0"), rel("a", "1.0.0")]))
}

# Design 2 (platforms are not solved): a package that names another platform version fails, also a lower one
expect {
	root = [pf(rel("basic-cli", "0.25.1")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [pf(rel("basic-cli", "0.25.0"))])])
	match Mvs.select(root, deps) {
		Err(PlatformMismatch(urls)) => Set.from_list(urls.map(|u| u.to_str())) == Set.from_list([rel("basic-cli", "0.25.1"), rel("basic-cli", "0.25.0")])
		_ => Bool.False
	}
}

## The error tag of a result, as text, so that a test can check the kind of error only.
error_kind : Try(List(PackageUrl), _) -> Str
error_kind = |result| match result {
	Ok(_) => "ok"
	Err(Cycle(_)) => "cycle"
	Err(RootConflict(_)) => "root"
	Err(ContentConflict(_)) => "content"
	Err(VersionConflict(_)) => "version"
	Err(PlatformMismatch(_)) => "platform"
}

## The same URL as `rel`, with http in place of https.
rel_http : Str, Str -> Str
rel_http = |name, version| rel(name, version).replace_first("https://", "http://")

# Settled Q1 (no cycle): a 1.0.0 names b 1.0.0, and b 1.0.0 names a 2.0.0 of the group of a
expect {
	root = [dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("b", "1.0.0"))]), (rel("b", "1.0.0"), [dep(rel("a", "1.1.0"))])])
	error_kind(Mvs.select(root, deps)) == "cycle"
}

# Settled Q1 (no cycle): a package that names its own group
expect {
	root = [dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("a", "1.2.0"))])])
	error_kind(Mvs.select(root, deps)) == "cycle"
}

# Settled Q1 (reached): a cycle through a version that is not selected is a cycle too
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("x", "1.0.0"))]
	deps = graph([
		(rel("a", "1.0.0"), [dep(rel("b", "1.0.0"))]),
		(rel("x", "1.0.0"), [dep(rel("b", "1.1.0"))]),
		(rel("b", "1.0.0"), [dep(rel("a", "1.0.0"))]),
	])
	error_kind(Mvs.select(root, deps)) == "cycle"
}

# Settled Q1, R-ID1: a 1.0.0 that names a 2.0.0 is not a cycle, because series 1 and 2 are two groups
expect {
	root = [dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("a", "2.0.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("a", "2.0.0")]))
}

# Settled Q2 (one hash): two hashes for a version that is not selected are a ContentConflict too
expect {
	other = "https://github.com/o/c/releases/download/1.0.0/${hash_of("other", "x")}.tar.zst"
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0")), dep(rel("x", "1.0.0"))]
	deps = graph([
		(rel("a", "1.0.0"), [dep(rel("c", "1.0.0"))]),
		(rel("b", "1.0.0"), [dep(other)]),
		(rel("x", "1.0.0"), [dep(rel("c", "1.2.0"))]),
	])
	error_kind(Mvs.select(root, deps)) == "content"
}

# Settled Q3 (root is exact): two root edges of one group with two versions
expect {
	root = [dep(rel("c", "1.0.0")), dep(rel("c", "1.2.0"))]
	match Mvs.select(root, |_| []) {
		Err(RootConflict(urls)) => Set.from_list(urls.map(|u| u.to_str())) == Set.from_list([rel("c", "1.0.0"), rel("c", "1.2.0")])
		_ => Bool.False
	}
}

# Settled Q3: two root edges with the same URL are not a conflict
expect selected([dep(rel("c", "1.0.0")), dep(rel("c", "1.0.0"))], |_| []) == Ok(Set.from_list([rel("c", "1.0.0")]))

# Settled Q4 (one text): the text of the root edge wins over another text of the same group, version and hash
expect {
	root = [dep(rel("c", "1.0.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel_http("c", "1.0.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("c", "1.0.0")]))
}

# Settled Q4 (one text): with no root edge, the first text in byte order wins (http:// before https://)
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.0.0"))]), (rel("b", "1.0.0"), [dep(rel_http("c", "1.0.0"))])])
	selected(root, deps) == Ok(Set.from_list([rel("a", "1.0.0"), rel("b", "1.0.0"), rel_http("c", "1.0.0")]))
}

# Settled Q1, Q3 (error order): a cycle and a version conflict give Cycle
expect {
	root = [dep(rel("a", "1.0.0")), dep(rel("c", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.5.0")), dep(rel("b", "1.0.0"))]), (rel("b", "1.0.0"), [dep(rel("a", "1.0.0"))])])
	error_kind(Mvs.select(root, deps)) == "cycle"
}

# Settled Q3 (error order): a root conflict and a version conflict give RootConflict
expect {
	root = [dep(rel("c", "1.0.0")), dep(rel("c", "1.2.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.5.0"))])])
	error_kind(Mvs.select(root, deps)) == "root"
}

# Settled Q2 (error order): a content conflict and a version conflict give ContentConflict
expect {
	other = "https://github.com/o/c/releases/download/1.5.0/${hash_of("other", "y")}.tar.zst"
	root = [dep(rel("c", "1.0.0")), dep(rel("a", "1.0.0")), dep(rel("b", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("c", "1.5.0"))]), (rel("b", "1.0.0"), [dep(other)])])
	error_kind(Mvs.select(root, deps)) == "content"
}

# Settled Q1, Q3 (error order): a cycle and a root conflict give Cycle
expect {
	root = [dep(rel("c", "1.0.0")), dep(rel("c", "1.2.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [dep(rel("b", "1.0.0"))]), (rel("b", "1.0.0"), [dep(rel("a", "1.0.0"))])])
	error_kind(Mvs.select(root, deps)) == "cycle"
}

# Mvs doc (error order): a version conflict and a platform mismatch give VersionConflict
expect {
	root = [pf(rel("basic-cli", "0.25.1")), dep(rel("http", "1.0.0")), dep(rel("a", "1.0.0"))]
	deps = graph([(rel("a", "1.0.0"), [pf(rel("basic-cli", "0.25.0")), dep(rel("http", "1.9.0"))])])
	error_kind(Mvs.select(root, deps)) == "version"
}
