app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Mvs
import pkg.PackageUrl

# TESTING.md 4 (MVS and group key): Mvs.select gives the same result as a second, independent
# implementation of the rule, for random graphs. The oracle below is written from the rule text of
# Design 2 only (clean room, R-GA7):
#
# | Design 2 fact or settled rule | Oracle |
# | --- | --- |
# | Per group, the highest version that any edge names wins for the whole graph | `best` |
# | Only the winner's deps are followed | edges come from the root and from winners only |
# | An app pin that is lower than a dependency needs fails | `$conflict` |
# | An app pin that is higher wins silently | the pin is the winner |
# | Settled Q1: a cycle in the groups of the reached packages (at any version) is `Cycle` | `order` |
# | Settled Q1: with no cycle, the groups are done in dependency order | `order` |
# | Settled error order: `Cycle` before `VersionConflict` | `oracle` |
#
# Most edges go to a later group. A package can also name an earlier group or its own group
# (odds 1 in 16), which can make a cycle. Each group and version has one hash, the root names
# each group at most once, and no edge is a platform edge (L0 tests those rules).
#
# Groups: 7 at most. Groups 0 and 1 share one URL form with series 1 and 2, groups 2 and 3 too,
# groups 4 and 5 share one URL form with series 0.3 and 0.4 (R-ID1: two series are two groups).

## The URL form index and the version of version index `j` (0 to 2) of group `g`.
version : U64, U64 -> (U64, { major : U64, minor : U64, patch : U64 })
version = |g, j| {
	step = [2, 9, 10].get(j) ?? 2
	if g == 4 or g == 5 {
		(2, { major: 0, minor: g - 1, patch: step })
	} else {
		(g // 2, { major: g % 2 + 1, minor: step, patch: 0 })
	}
}

base58 : List(U8)
base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".to_utf8()

url_text : U64, U64 -> Str
url_text = |g, j| {
	(form, v) = version(g, j)
	hash = Str.from_utf8([base58.get(g) ?? '1', base58.get(j) ?? '1'].concat(List.repeat('z', 42))) ?? "bad"
	"https://github.com/o/p${form.to_str()}/releases/download/${v.major.to_str()}.${v.minor.to_str()}.${v.patch.to_str()}/${hash}.tar.zst"
}

## A graph: the number of groups, the number of versions of each group, the root edges, and the
## deps of each package. An edge is (group, version index).
Graph : { n : U64, counts : List(U64), root : List((U64, U64)), deps : List(((U64, U64), List((U64, U64)))) }

decode : List(U8) -> Graph
decode = |bytes| {
	var $pos = 0
	var $counts = []
	var $root = []
	var $deps = []
	n = 2 + (bytes.get(0) ?? 0).to_u64() % 6
	$pos = 1
	for _g in 0.U64..<n {
		$counts = $counts.append(1 + (bytes.get($pos) ?? 0).to_u64() % 3)
		$pos = $pos + 1
	}
	for g in 0.U64..<n {
		b = (bytes.get($pos) ?? 0).to_u64()
		$pos = $pos + 1
		# The root names group 0, and each other group with odds 1 in 2.
		if g == 0 or b % 2 == 0 {
			$root = $root.append((g, (b // 2) % ($counts.get(g) ?? 1)))
		}
	}
	for g in 0.U64..<n {
		for j in 0.U64..<($counts.get(g) ?? 1) {
			var $edges = []
			for h in (g + 1)..<n {
				b = (bytes.get($pos) ?? 0).to_u64()
				$pos = $pos + 1
				if b % 2 == 0 {
					$edges = $edges.append((h, (b // 2) % ($counts.get(h) ?? 1)))
				}
			}
			# An edge back to an earlier group or to its own group, with odds 1 in 16. A missing
			# byte (0) gives none.
			back = (bytes.get($pos) ?? 0).to_u64()
			$pos = $pos + 1
			if back % 16 == 15 {
				h = (back // 16) % (g + 1)
				$edges = $edges.append((h, (back // 16) % ($counts.get(h) ?? 1)))
			}
			$deps = $deps.append(((g, j), $edges))
		}
	}
	{ n, counts: $counts, root: $root, deps: $deps }
}

deps_of : Graph, (U64, U64) -> List((U64, U64))
deps_of = |graph, node| graph.deps.find_first(|(key, _)| key == node).map_ok(|(_, edges)| edges) ?? []

## Version order: compare the numbers as numbers, major first.
higher : { major : U64, minor : U64, patch : U64 }, { major : U64, minor : U64, patch : U64 } -> Bool
higher = |a, b| a.major > b.major or (a.major == b.major and (a.minor > b.minor or (a.minor == b.minor and a.patch > b.patch)))

## The packages that the root reaches through any edge, at any version (settled Q1).
reached : Graph -> List((U64, U64))
reached = |graph| {
	var $seen = []
	var $todo = graph.root
	while !$todo.is_empty() {
		node = $todo.first() ?? (0, 0)
		$todo = $todo.drop_first(1)
		if !$seen.contains(node) {
			$seen = $seen.append(node)
			$todo = $todo.concat(deps_of(graph, node))
		}
	}
	$seen
}

## The groups of the reached packages in dependency order (Kahn), or Err when they form a cycle.
order : Graph, List((U64, U64)) -> Try(List(U64), [Cycle])
order = |graph, nodes| {
	groups = Set.to_list(Set.from_list(nodes.map(|(g, _)| g)))
	edges = Set.to_list(Set.from_list(nodes.join_map(|(g, j)| deps_of(graph, (g, j)).map(|(h, _)| (g, h)))))
	var $done = []
	var $left = groups
	var $moved = Bool.True
	while $moved {
		$moved = Bool.False
		ready = $left.keep_if(|h| !edges.any(|(from, to)| to == h and !$done.contains(from)))
		if !ready.is_empty() {
			$done = $done.concat(ready)
			$left = $left.keep_if(|h| !ready.contains(h))
			$moved = Bool.True
		}
	}
	if $left.is_empty() Ok($done) else Err(Cycle)
}

## The oracle: the URL texts of the winners, or Err(Cycle), or Err(Conflict) when a root pin is
## lower than a followed edge.
oracle : Graph -> Try(Set(Str), [Cycle, Conflict])
oracle = |graph| {
	done = order(graph, reached(graph))?
	var $winners = []
	var $conflict = Bool.False
	for g in done {
		pin = graph.root.find_first(|(h, _)| h == g)
		needs = $winners.join_map(|(h, w)| deps_of(graph, (h, w)).keep_if(|(t, _)| t == g).map(|(_, j)| j))
		match pin {
			Ok((_, p)) => {
				if needs.any(|j| higher(version(g, j).1, version(g, p).1)) {
					$conflict = Bool.True
				}
				$winners = $winners.append((g, p))
			}

			Err(_) =>
				match needs.first() {
					Ok(first) => {
						best = needs.fold(first, |acc, j| if higher(version(g, j).1, version(g, acc).1) j else acc)
						$winners = $winners.append((g, best))
					}

					Err(_) => {}
				}
		}
	}
	if $conflict Err(Conflict) else Ok(Set.from_list($winners.map(|(g, j)| url_text(g, j))))
}

url_of : U64, U64 -> PackageUrl
url_of = |g, j| match PackageUrl.parse(url_text(g, j)) {
	Ok(u) => u
	Err(_) => crash "a generated URL did not parse"
}

test : List(U8) -> Fuzz.Outcome
test = |bytes| {
	graph = decode(bytes)
	edge = |(g, j)| { url: url_of(g, j), is_platform: Bool.False }
	table = graph.deps.map(|((g, j), edges)| (url_text(g, j), edges.map(edge)))
	deps = |u| table.find_first(|(text, _)| text == u.to_str()).map_ok(|(_, edges)| edges) ?? []
	got = Mvs.select(graph.root.map(edge), deps)
	agrees = match (oracle(graph), got) {
		(Ok(want), Ok(urls)) => urls.len() == want.len() and Set.from_list(urls.map(|u| u.to_str())) == want
		(Err(Cycle), Err(Cycle(_))) => Bool.True
		(Err(Conflict), Err(VersionConflict(_))) => Bool.True
		_ => Bool.False
	}
	if agrees Fuzz.keep else crash "Mvs.select disagrees with the oracle"
}

target = Fuzz.target_with({
	name: "mvs-oracle",
	generator: Fuzz.bytes,
	test,
	show: |bytes| {
		graph = decode(bytes)
		"${Str.inspect(graph)} oracle: ${Str.inspect(oracle(graph))}"
	},
})
