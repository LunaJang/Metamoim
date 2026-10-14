#!/bin/bash
# The groups must not depend on how the work was divided. Runs one binary over a grid
# of --threads x --partitions and compares every result against the first cell.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${BIN:-$HERE/../build/src/metamoim}
WORK=${WORK:-$HERE/work_invariance}
FIXTURE=$HERE/fixture
CKL=${CKL:-$HERE/work_golden/fixture/ckl}

THREAD_GRID=${THREAD_GRID:-"1 4 16"}
PARTITION_GRID=${PARTITION_GRID:-"1 4 16"}
MODE=${MODE:-grouping}

[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 1; }
[ -f "$CKL/kmer_params" ] || { echo "no common k-mer list at $CKL; run run_golden.sh first" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"

ref=""
fail=0
for t in $THREAD_GRID; do
    for p in $PARTITION_GRID; do
        d=$WORK/t${t}_p${p}
        mkdir -p "$d"
        "$BIN" "$MODE" --threads "$t" --partitions "$p" \
            "$FIXTURE/reads/R1.fq" "$FIXTURE/reads/R2.fq" "$CKL" "$d" \
            > "$d/run.log" 2>&1 || { printf '%-14s %s\n' "t=$t p=$p" "RUN FAILED"; fail=1; continue; }
        if [ -z "$ref" ]; then
            ref=$d
            printf '%-14s %s\n' "t=$t p=$p" "reference"
            continue
        fi
        bad=""
        for f in groups groupMap skipped_kmers; do
            cmp -s "$ref/$f" "$d/$f" || bad="$bad $f"
        done
        if [ -z "$bad" ]; then printf '%-14s %s\n' "t=$t p=$p" "identical"
        else printf '%-14s %s\n' "t=$t p=$p" "DIFFER:$bad"; fail=1; fi
    done
done

echo
[ "$fail" -eq 0 ] && echo "RESULT: $MODE is invariant over the grid" || echo "RESULT: FAILED"
exit $fail
