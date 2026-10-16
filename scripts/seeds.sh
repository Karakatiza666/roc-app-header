#!/bin/bash
# Copies the seed headers into tests/fixtures/seeds/ and makes the expected
# values with tools outside this package:
#   <name>.main.roc.txt  the file as it is in the roc package cache
#   <name>.fmt.roc.txt   the same file after `roc fmt` (the pinned roc)
#   <name>.deps.tsv      the sidecar that roc wrote (<hash>.deps.json): kind and deps
# Usage: scripts/seeds.sh [ROC]. ROC defaults to `roc` on PATH. Run it by hand when the seed list
# changes. The 2 app seeds come from a checkout of github.com/roc-talon/talon in $TALON_DIR;
# with no TALON_DIR they are skipped (their old files stay). The cache is $SEED_CACHE, else
# $XDG_CACHE_HOME/roc, else ~/.cache/roc. SOURCES.tsv names each source with no local path:
# `$XDG_CACHE_HOME/roc/packages/<hash>/main.roc`, or `github.com/roc-talon/talon: <path>`.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
ROC=${1:-roc}
CACHE=${SEED_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/roc}/packages
TALON_DIR=${TALON_DIR:-}
OUT=${OUT:-$HERE/tests/fixtures/seeds}
W=$HERE/.work/seeds
rm -rf "$W"; mkdir -p "$W" "$OUT"
# No `..` in these paths: roc stops with PathOutsideWorkspace.
export XDG_CACHE_HOME=$W/xdg ROC_CACHE_DIR=$W/xdg/roc

# name | hash or Talon path | release URL | license | copyright line of the source LICENSE
SEEDS=$(cat <<'T'
unicode-4.2.0|4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w|https://github.com/roc-lang/unicode/releases/download/4.2.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst|UPL-1.0|Copyright © 2019 Richard Feldman and subsequent Roc authors <roc-lang.org/authors>
http-1.0.0|6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS|https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst|UPL-1.0|Copyright © 2025 Richard Feldman and subsequent Roc authors <roc-lang.org/authors>
path-4.0.0|7YfABZPwJAXtLBY2vm8FqMyGAtNxncCJ65HdNKHFGNnE|https://github.com/roc-lang/path/releases/download/4.0.0/7YfABZPwJAXtLBY2vm8FqMyGAtNxncCJ65HdNKHFGNnE.tar.zst|UPL-1.0|Copyright © 2019 Richard Feldman and subsequent Roc authors <roc-lang.org/authors>
roc-parser-2.0.0|7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW|https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst|UPL-1.0|Copyright © 2023 Luke Boswell and subsequent authors <https://github.com/lukewilliamboswell/roc-parser/graphs/contributors>
roc-ansi-0.13.0|JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL|https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst|UPL-1.0|Copyright © 2023 Luke Boswell and subsequent authors
roc-random-0.9.2|2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc|https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst|UPL-1.0|Copyright © 2022 Jan Van Bruggen and subsequent roc-random authors <https://github.com/JanCVanB/roc-random/graphs/contributors>
basic-cli-0.25.0|CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA|https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst|UPL-1.0|Copyright © 2022 Richard Feldman and subsequent basic-cli authors <github.com/roc-lang/basic-cli/graphs/contributors>
basic-cli-0.29.0|GrSTLEKd6yw8orQ5ByQQVY3Htg59vZYaoHBvQELueiMB|https://github.com/roc-lang/basic-cli/releases/download/0.29.0/GrSTLEKd6yw8orQ5ByQQVY3Htg59vZYaoHBvQELueiMB.tar.zst|UPL-1.0|Copyright © 2022 Richard Feldman and subsequent basic-cli authors <github.com/roc-lang/basic-cli/graphs/contributors>
basic-webserver-0.17.0|AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT|https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst|UPL-1.0|Copyright © 2023 Richard Feldman and subsequent Roc authors <roc-lang.org/authors>
roc-ray-0.10.0|5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9|https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst|UPL-1.0|Copyright © 2024 Luke Boswell and subsequent authors
template-zig-1.0.0|AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq|https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst|UPL-1.0|Copyright © 2024 Luke Boswell and subsequent authors
template-zig-x|ABFgWwu8SwPJfp7tzxDoTL41b1jFeHEac3RxUFSt1WWp|https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/x/ABFgWwu8SwPJfp7tzxDoTL41b1jFeHEac3RxUFSt1WWp.tar.zst|UPL-1.0|Copyright © 2024 Luke Boswell and subsequent authors
roc-s2-geometry|Gv7JYaeoUsB84nSdFrAX1B24jWHeYZvAcyR7BRa62oSA|(unknown: not in a header in the cache)|UPL-1.0 (SPDX line in the file; upstream Apache-2.0 notice kept in the file)|SPDX-FileCopyrightText: 2026 George Bulakh
app-webserver|conformance/host-link/apps/basic-webserver-0.17.0.roc|(Talon repository file)|UPL-1.0|Copyright © 2026 Heorhii Bulakh and subsequent Talon authors <github.com/roc-talon/talon/graphs/contributors>
app-print|conformance/build-share/apps/print.roc|(Talon repository file)|UPL-1.0|Copyright © 2026 Heorhii Bulakh and subsequent Talon authors <github.com/roc-talon/talon/graphs/contributors>
T
)

## True for a row whose source is a Talon file (a path), not a cache hash.
is_talon() { case "$1" in */*) return 0 ;; *) return 1 ;; esac; }

{
	printf 'name\tsource path\trelease URL\tlicense\tcopyright\n'
	while IFS='|' read -r name src url lic copy; do
		if is_talon "$src"; then path="github.com/roc-talon/talon: $src"; else path="\$XDG_CACHE_HOME/roc/packages/$src/main.roc"; fi
		printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$path" "$url" "$lic" "$copy"
	done <<<"$SEEDS"
} >"$OUT/SOURCES.tsv"

while IFS='|' read -r name src _url _lic _copy; do
	if is_talon "$src"; then
		if [ -z "$TALON_DIR" ]; then echo "$name: skipped (no TALON_DIR)"; continue; fi
		path=$TALON_DIR/$src; sidecar=
	else
		path=$CACHE/$src/main.roc; sidecar=$CACHE/$src.deps.json
	fi
	cp "$path" "$OUT/$name.main.roc.txt"
	mkdir -p "$W/$name"; cp "$path" "$W/$name/main.roc"
	if "$ROC" fmt "$W/$name/main.roc" >"$W/$name/fmt.log" 2>&1; then
		cp "$W/$name/main.roc" "$OUT/$name.fmt.roc.txt"
	else
		echo "roc fmt failed for $name (see $W/$name/fmt.log)"; rm -f "$OUT/$name.fmt.roc.txt"
	fi
	if [ -n "$sidecar" ] && [ -f "$sidecar" ]; then
		jq -r '"kind\t" + .kind, (.deps[] | "dep\t" + .alias + "\t" + .spec + "\t" + (.is_platform | tostring))' "$sidecar" >"$OUT/$name.deps.tsv"
	else
		rm -f "$OUT/$name.deps.tsv"
	fi
	echo "$name: $(wc -l <"$path") lines$([ -f "$OUT/$name.deps.tsv" ] && echo ', sidecar')$([ -f "$OUT/$name.fmt.roc.txt" ] && ! cmp -s "$path" "$OUT/$name.fmt.roc.txt" && echo ', fmt changed it')"
done <<<"$SEEDS"
