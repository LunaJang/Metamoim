#!/bin/bash
# Compare this build's output against the output committed under test/golden.
#
# This is the check that runs on every push. It needs metamoim and nothing else: the
# expected answer is a file in the repository, not another program's output. When it
# fails, either the change was not meant to reach the output -- fix it -- or it was, and
# then `--update` puts the new golden in the same commit for the reviewer to read.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pipeline.sh"

BIN=${BIN:-$HERE/../build/src/metamoim}
GOLDEN=${GOLDEN:-$HERE/golden}
WORK=${WORK:-$HERE/work_golden}
FIXTURES=${FIXTURES:-"fixture fixture_real"}
THREADS=${THREADS:-8}
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 1; }

rm -rf "$WORK"
fail=0
for name in $FIXTURES; do
    fixture=$HERE/$name
    [ -d "$fixture" ] || { echo "no fixture at $fixture; run its make_*.py first" >&2; exit 1; }
    d=$WORK/$name
    g=$GOLDEN/$name
    mkdir -p "$d" "$g"

    load_fixture_conf "$fixture"
    run_pipeline "$BIN" "$fixture" "$d" "$THREADS" 16 || { fail=1; continue; }

    ( cd "$d" && for f in $PIPELINE_OUTPUTS; do sha256sum "$f"; done ) > "$d/manifest.sha256"
    BIN="$BIN" "$HERE/summarize.sh" "$d" "$fixture" > "$d/summary.txt"

    if [ "$UPDATE" = 1 ]; then
        cp "$d/manifest.sha256" "$d/summary.txt" "$g/"
        echo "updated $g"
        continue
    fi

    for f in manifest.sha256 summary.txt; do
        if [ ! -f "$g/$f" ]; then
            echo "[$name] no golden $f -- run './test/run_golden.sh --update' once"
            fail=1
        elif cmp -s "$g/$f" "$d/$f"; then
            printf '[%s] %-18s matches\n' "$name" "$f"
        else
            printf '[%s] %-18s DIFFERS\n' "$name" "$f"
            diff "$g/$f" "$d/$f" | head -40 | sed 's/^/    /'
            fail=1
        fi
    done
done

echo
if [ "$UPDATE" = 1 ]; then
    echo "golden rewritten. Commit test/golden with the change that moved it, so the diff"
    echo "is reviewed next to its cause."
elif [ "$fail" -eq 0 ]; then
    echo "RESULT: output matches the committed golden"
else
    echo "RESULT: FAILED"
fi
exit $fail
