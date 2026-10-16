#!/bin/bash
# All checks of the package: check, fmt, L0 (roc test), L1 (roc-fuzz, fixed run count, TW6).
# Usage: scripts/test.sh [ROC [FUZZ_ROC]]. ROC (default: `roc` on PATH) runs check, fmt and
# L0. FUZZ_ROC builds the fuzz targets (default: ROC). RUNS sets the fuzz run count (default 20000).
# Exit 0 only when all pass.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
ROC=${1:-roc}
FUZZ_ROC=${2:-$ROC}
RUNS=${RUNS:-20000}
# One work dir for each compiler, so that two nightlies do not share a cache.
W=$HERE/.work/$("$ROC" version | awk '{print $NF}')
mkdir -p "$W/fuzz"
# No `..` in these paths: roc stops with PathOutsideWorkspace.
export XDG_CACHE_HOME=$W/xdg ROC_CACHE_DIR=$W/xdg/roc
cd "$HERE"
FAIL=0
step() { echo; echo "== $*"; }
result() { # name exit
	if [ "$2" = 0 ]; then echo "pass: $1"; else echo "FAIL: $1 (exit $2)"; FAIL=1; fi
}

step "check"
"$ROC" check package/main.roc; result "check package/main.roc" $?
for f in tests/*.roc fuzz/*.roc; do
	"$ROC" check "$f" >"$W/check.log" 2>&1; rc=$?
	[ $rc = 0 ] || cat "$W/check.log"
	result "check $f" $rc
done

step "fmt"
"$ROC" fmt --check package tests fuzz; result "fmt --check" $?

step "L0"
for f in tests/*.roc; do
	"$ROC" test "$f" --no-cache 2>&1 | tail -4; result "test $f" "${PIPESTATUS[0]}"
done

step "L1, $RUNS runs, seed 1"
for f in fuzz/*.roc; do
	n=$(basename "$f" .roc)
	"$FUZZ_ROC" build --fuzz "$f" --output="$W/fuzz/$n" >"$W/fuzz/$n.build.log" 2>&1; rc=$?
	result "build $f" $rc
	[ $rc = 0 ] || continue
	rm -rf "$W/fuzz/art-$n"
	"$W/fuzz/$n" run --runs="$RUNS" --seed=1 --time=0 --artifact-dir="$W/fuzz/art-$n" >"$W/fuzz/$n.log" 2>&1; rc=$?
	grep -m1 -E '^Done|roc crashed' "$W/fuzz/$n.log"
	result "fuzz $n" $rc
done

echo
if [ $FAIL = 0 ]; then echo "ALL PASS"; else echo "SOME CHECKS FAIL"; exit 1; fi
