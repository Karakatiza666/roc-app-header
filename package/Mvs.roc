import PackageUrl

## Minimal version selection, with the rules of the Roc compiler.
##
## | Rule | Text |
## | --- | --- |
## | Reached | A package is reached when the root or a reached package names it, at any version. |
## | No cycle | When the groups of the reached packages form a cycle (a package names its own group, or `a 1.0.0` names `b 1.0.0` and that names a version of `a`), the result is `Cycle`. |
## | Order | With no cycle, the groups are done in dependency order. A group is done only after each group whose reached packages name it. |
## | Highest wins | In each group, the highest version that a followed edge names is used for the whole graph. Versions compare as three numbers, major first. |
## | Winners only | The followed edges are the root edges and the dependencies of the selected version of each group. Other edges have no effect. |
## | Root is exact | A root edge is exact. Two root edges of one group with two versions are a `RootConflict`. A followed edge that needs a higher version than the root edge of its group is a `VersionConflict`. A lower one is not. |
## | One hash | Two followed edges with the same group and version and two hashes are a `ContentConflict`, also when that version is not selected. |
## | One text | When followed edges give one group, version and hash with two URL texts (`http://` and `https://`), the result has the text of the root edge, else the first text in byte order. |
## | Platforms | A platform edge is not solved. All followed platform edges must have the same group, version and hash, else `PlatformMismatch`. The dependencies of the platform are followed. |
## | Error order | When there is more than one kind of error, the result is the first kind in this order: `Cycle`, `RootConflict`, `ContentConflict`, `VersionConflict`, `PlatformMismatch`. |
Mvs :: [].{

	## Selects one version for each group that the root reaches.
	##
	## `root` is the dependency record of the root header (an app). `deps` gives
	## the dependency record of the package at a URL. The result has one URL
	## for each group in the build, the platform included. Its order is not
	## part of the contract. Each error lists all its cases, in no fixed order.
	## `Cycle` lists the packages on one cycle.
	select :
		List({ url : PackageUrl, is_platform : Bool }),
		(PackageUrl -> List({ url : PackageUrl, is_platform : Bool })) -> Try(
			List(PackageUrl),
			[
				Cycle(List(PackageUrl)),
				RootConflict(List(PackageUrl)),
				ContentConflict(List(PackageUrl)),
				VersionConflict(List({ pinned : PackageUrl, needed : PackageUrl, by : PackageUrl })),
				PlatformMismatch(List(PackageUrl)),
			],
		)
	select = |root, deps| {
		nodes = reach(root, deps)
		order = match dependency_order(nodes) {
			Ok(groups) => groups
			Err(cycle) => return Err(Cycle(cycle))
		}
		root_conflicts = root_conflicts_of(root)
		if !root_conflicts.is_empty() {
			return Err(RootConflict(root_conflicts))
		}
		{ chosen, followed } = choose(root, nodes, order)
		content = content_conflicts(followed)
		if !content.is_empty() {
			return Err(ContentConflict(content))
		}
		versions = version_conflicts(root, followed)
		if !versions.is_empty() {
			return Err(VersionConflict(versions))
		}
		platforms = platform_mismatches(followed)
		if !platforms.is_empty() {
			return Err(PlatformMismatch(platforms))
		}
		Ok(chosen)
	}
}

Edge : { url : PackageUrl, is_platform : Bool }

Group : { form : Str, series : Str }

## A reached package and its dependency record.
Node : { url : PackageUrl, deps : List(Edge) }

## An edge that the selection follows, and the package that names it (none for a root edge).
Followed : { edge : Edge, by : [Root, By(PackageUrl)] }

## Each package that the root reaches at any version, by URL text.
reach : List(Edge), (PackageUrl -> List(Edge)) -> Dict(Str, Node)
reach = |root, deps| {
	var $nodes = Dict.empty()
	var $pending = root.map(|e| e.url)
	while !$pending.is_empty() {
		match $pending.last() {
			Ok(url) => {
				$pending = $pending.drop_last(1)
				if !$nodes.contains(url.to_str()) {
					record = deps(url)
					$nodes = $nodes.insert(url.to_str(), { url, deps: record })
					$pending = $pending.concat(record.map(|e| e.url))
				}
			}

			Err(_) => break
		}
	}
	$nodes
}

## The groups that each group names, from all reached packages.
group_edges : Dict(Str, Node) -> Dict(Group, Set(Group))
group_edges = |nodes| nodes.fold(
	Dict.empty(),
	|acc, _, node| {
		from = node.url.group()
		start = if acc.contains(from) acc else acc.insert(from, Set.empty())
		node.deps.fold(
			start,
			|inner, e| {
				to = e.url.group()
				with_to = if inner.contains(to) inner else inner.insert(to, Set.empty())
				with_to.update(from, |old| Ok((old ?? Set.empty()).insert(to)))
			},
		)
	},
)

## The groups in dependency order: a group comes after each group that names it.
## A cycle gives the packages on one cycle.
dependency_order : Dict(Str, Node) -> Try(List(Group), List(PackageUrl))
dependency_order = |nodes| {
	succ = group_edges(nodes)
	var $indegree = succ.map(|_, _| 0)
	for (_, named) in succ {
		for t in named {
			$indegree = $indegree.update(t, |n| Ok((n ?? 0) + 1))
		}
	}
	var $ready = $indegree.keep_if(|(_, n)| n == 0).keys()
	var $order = []
	while !$ready.is_empty() {
		match $ready.last() {
			Ok(g) => {
				$ready = $ready.drop_last(1)
				$order = $order.append(g)
				for t in succ.get(g) ?? Set.empty() {
					left = ($indegree.get(t) ?? 1) - 1
					$indegree = $indegree.insert(t, left)
					if left == 0 {
						$ready = $ready.append(t)
					}
				}
			}

			Err(_) => break
		}
	}
	if $order.len() == succ.len() {
		Ok($order)
	} else {
		done = Set.from_list($order)
		Err(cycle_urls(nodes, succ.keep_if(|(g, _)| !done.contains(g))))
	}
}

## One cycle in the groups that are left after the dependency order. Each of
## them has a group that names it in the rest, so a walk back finds a cycle.
cycle_urls : Dict(Str, Node), Dict(Group, Set(Group)) -> List(PackageUrl)
cycle_urls = |nodes, rest| {
	preds = |g| rest.keep_if(|(_, named)| named.contains(g)).keys()
	var $path = rest.keys().take_first(1)
	var $cycle = []
	while $cycle.is_empty() and !$path.is_empty() {
		current = $path.last() ?? { form: "", series: "" }
		match preds(current) {
			[p, ..] =>
				match $path.find_first_index(|g| g == p) {
					Ok(k) => {
						# The walk goes back, so the cycle in forward order is the reverse.
						$cycle = $path.drop_first(k).rev()
					}

					Err(_) => {
						$path = $path.append(p)
					}
				}

			[] => break
		}
	}
	# For each group, a package in it that names the next group of the cycle.
	n = $cycle.len()
	$cycle.map_with_index(
		|g, i| {
			next = $cycle.get((i + 1) % n) ?? g
			found = nodes.values().find_first(|node| node.url.group() == g and node.deps.any(|e| e.url.group() == next))
			found.map_ok(|node| node.url)
		},
	).keep_oks(|t| t)
}

## The groups in which the root edges give two or more versions: all the root URLs of those groups.
root_conflicts_of : List(Edge) -> List(PackageUrl)
root_conflicts_of = |root| {
	urls = root.map(|e| e.url)
	unique_texts(urls.keep_if(|u| urls.any(|other| other.group() == u.group() and other.version() != u.version())))
}

## Highest wins, in dependency order. Only the edges of the selected packages are followed.
choose : List(Edge), Dict(Str, Node), List(Group) -> { chosen : List(PackageUrl), followed : List(Followed) }
choose = |root, nodes, order| {
	var $followed = root.map(|e| { edge: e, by: Root })
	var $chosen = []
	for g in order {
		into = $followed.keep_if(|f| f.edge.url.group() == g)
		match winner(into) {
			Ok(url) => {
				$chosen = $chosen.append(url)
				record = (nodes.get(url.to_str()) ?? { url, deps: [] }).deps
				$followed = $followed.concat(record.map(|e| { edge: e, by: By(url) }))
			}

			Err(_) => {}
		}
	}
	{ chosen: $chosen, followed: $followed }
}

## The selected URL of one group: the root version, else the highest version.
## Of the URL texts of that version, the root text, else the first in byte order.
winner : List(Followed) -> Try(PackageUrl, [NoEdge])
winner = |into| {
	roots = into.keep_if(|f| f.by == Root).map(|f| f.edge.url)
	urls = into.map(|f| f.edge.url)
	if !roots.is_empty() {
		first_text(roots)
	} else {
		top = urls.fold(
			urls.first() ?? return Err(NoEdge),
			|best, u| if newer(u, best) u else best,
		)
		first_text(urls.keep_if(|u| u.version() == top.version()))
	}
}

## True when `a` has a higher version than `b`. The three numbers compare as numbers, major first.
newer : PackageUrl, PackageUrl -> Bool
newer = |a, b| {
	x = a.version()
	y = b.version()
	if x.major != y.major {
		x.major > y.major
	} else if x.minor != y.minor {
		x.minor > y.minor
	} else {
		x.patch > y.patch
	}
}

## The URL whose text is first in byte order.
first_text : List(PackageUrl) -> Try(PackageUrl, [NoEdge])
first_text = |urls| match urls.first() {
	Ok(start) => Ok(urls.fold(start, |best, u| if bytes_before(u.to_str().to_utf8(), best.to_str().to_utf8()) u else best))
	Err(_) => Err(NoEdge)
}

## True when the bytes `a` come before the bytes `b`.
bytes_before : List(U8), List(U8) -> Bool
bytes_before = |a, b| {
	var $i = 0
	while $i < a.len() and $i < b.len() {
		x = a.get($i) ?? 0
		y = b.get($i) ?? 0
		if x != y {
			return x < y
		}
		$i = $i + 1
	}
	a.len() < b.len()
}

## The URLs with one URL for each text.
unique_texts : List(PackageUrl) -> List(PackageUrl)
unique_texts = |urls| urls.fold(
	{ seen: Set.empty(), out: [] },
	|acc, u| if acc.seen.contains(u.to_str()) acc else { seen: acc.seen.insert(u.to_str()), out: acc.out.append(u) },
).out

## The followed edges of one group and version with two or more hashes.
content_conflicts : List(Followed) -> List(PackageUrl)
content_conflicts = |followed| {
	urls = followed.map(|f| f.edge.url)
	same_release = |a, b| a.group() == b.group() and a.version() == b.version()
	unique_texts(urls.keep_if(|u| urls.any(|other| same_release(u, other) and other.hash() != u.hash())))
}

## Each followed edge that needs a higher version than the root edge of its group.
version_conflicts : List(Edge), List(Followed) -> List({ pinned : PackageUrl, needed : PackageUrl, by : PackageUrl })
version_conflicts = |root, followed| {
	found = followed.join_map(
		|f| match f.by {
			Root => []
			By(by) =>
				root
					.keep_if(|r| r.url.group() == f.edge.url.group() and newer(f.edge.url, r.url))
					.map(|r| { pinned: r.url, needed: f.edge.url, by })
		},
	)
	found.fold(
		{ seen: Set.empty(), out: [] },
		|acc, c| {
			key = (c.pinned.to_str(), c.needed.to_str(), c.by.to_str())
			if acc.seen.contains(key) acc else { seen: acc.seen.insert(key), out: acc.out.append(c) }
		},
	).out
}

## The followed platform edges, when they do not all have one group, version and hash.
platform_mismatches : List(Followed) -> List(PackageUrl)
platform_mismatches = |followed| {
	urls = followed.keep_if(|f| f.edge.is_platform).map(|f| f.edge.url)
	same = |a, b| a.group() == b.group() and a.version() == b.version() and a.hash() == b.hash()
	match urls {
		[first, ..] if urls.any(|u| !same(u, first)) => unique_texts(urls)
		_ => []
	}
}
