#!/bin/bash
# Checks that another roc gives the same seed expected values as tests/fixtures/seeds/:
#   1. `roc fmt` output (scripts/seeds.sh with OUT in .work)
#   2. the sidecar <hash>.deps.json: a new cache holds only the .roc files of each seed, and
#      `roc deps` on a package that names the hash makes roc write the sidecar again (R-FE9).
# Usage: scripts/seeds-check.sh ROC. Exit 0 when all are the same. The cache seeds are read from
# $XDG_CACHE_HOME/roc (default ~/.cache/roc). The 2 Talon app seeds need TALON_DIR (a checkout of
# github.com/roc-talon/talon); with no TALON_DIR they are skipped with a note.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
ROC=$1
FIX=$HERE/tests/fixtures/seeds
W=$HERE/.work/seeds-check-$("$ROC" version | awk '{print $NF}')
rm -rf "$W"; mkdir -p "$W/out" "$W/xdg/roc/packages"
FAIL=0

CACHE_ROOT=${XDG_CACHE_HOME:-$HOME/.cache}
XDG_CACHE_HOME=$CACHE_ROOT OUT=$W/out "$HERE/scripts/seeds.sh" "$ROC" >"$W/seeds.log" 2>&1
for f in "$FIX"/*.fmt.roc.txt; do
	b=$(basename "$f")
	n=${b%.fmt.roc.txt}
	if grep -q "^$n	github.com/roc-talon/talon: " "$FIX/SOURCES.tsv" && [ -z "${TALON_DIR:-}" ]; then
		echo "fmt skipped: $b (no TALON_DIR)"; continue
	fi
	if cmp -s "$f" "$W/out/$b"; then echo "fmt same: $b"; else echo "fmt DIFF: $b"; diff "$f" "$W/out/$b"; FAIL=1; fi
done

tail -n +2 "$FIX/SOURCES.tsv" | while IFS=$'\t' read -r name path _url _lic _copy; do
	case "$path" in '$XDG_CACHE_HOME/roc/packages/'*) ;; *) continue ;; esac
	src=$CACHE_ROOT/${path#\$XDG_CACHE_HOME/}; src=$(dirname "$src"); hash=$(basename "$src"); dst=$W/xdg/roc/packages/$hash
	mkdir -p "$dst"; (cd "$src" && find . -name '*.roc' -exec cp --parents {} "$dst" \;)
	# The host and version are not read: roc finds packages/<hash>/ by the hash.
	u="https://example.com/x/1.0.0/$hash.tar.zst"
	mkdir -p "$W/p-$name"
	if [ "$(head -1 "$FIX/$name.deps.tsv" | cut -f2)" = platform ]; then
		printf 'package [] { pf: platform "%s" }\n' "$u"
	else
		printf 'package [] { x: "%s" }\n' "$u"
	fi >"$W/p-$name/main.roc"
	XDG_CACHE_HOME=$W/xdg ROC_CACHE_DIR=$W/xdg/roc "$ROC" deps "$W/p-$name/main.roc" >"$W/p-$name/deps.log" 2>&1
	side=$W/xdg/roc/packages/$hash.deps.json
	if [ ! -f "$side" ]; then echo "sidecar MISSING: $name"; echo 1 >"$W/fail"; continue; fi
	jq -r '"kind\t" + .kind, (.deps[] | "dep\t" + .alias + "\t" + .spec + "\t" + (.is_platform | tostring))' "$side" >"$W/$name.deps.tsv"
	if cmp -s "$W/$name.deps.tsv" "$FIX/$name.deps.tsv"; then echo "sidecar same: $name"; else echo "sidecar DIFF: $name"; diff "$FIX/$name.deps.tsv" "$W/$name.deps.tsv"; echo 1 >"$W/fail"; fi
done
[ -f "$W/fail" ] && FAIL=1
[ $FAIL = 0 ] && echo "SAME" || { echo "DIFFERENT"; exit 1; }
