#!/bin/bash
# The flush schedule must not reach the output. Runs one fixture at a range of
# --max-buffered-pairs and requires every result to match the default-budget run, which
# flushes once.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${BIN:-$HERE/../build/src/metamoim}
WORK=${WORK:-$HERE/work_flush}
FIXTURE=${FIXTURE:-$HERE/fixture_real}
CKL=${CKL:-$HERE/work_real/metamoim_a/ckl}
BUDGETS=${BUDGETS:-"0 20000"}
THREADS=${THREADS:-8}

[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 1; }
[ -f "$CKL/kmer_params" ] || { echo "no common k-mer list at $CKL" >&2; exit 1; }

rm -rf "$WORK"
fail=0
for cmd in grouping easy-grouping; do
    ref=""
    for b in $BUDGETS; do
        d=$WORK/${cmd}_$b
        mkdir -p "$d"
        "$BIN" "$cmd" --threads "$THREADS" --max-buffered-pairs "$b" \
            "$FIXTURE/reads/R1.fq" "$FIXTURE/reads/R2.fq" "$CKL" "$d" \
            > "$d/run.log" 2>&1 || { printf '%-16s %-8s %s\n' "$cmd" "$b" "RUN FAILED"; fail=1; continue; }
        rounds=$(grep -oE "over [0-9]+ rounds" "$d/run.log" | grep -oE "[0-9]+")
        if [ -z "$ref" ]; then
            ref=$d
            printf '%-16s %-8s %-12s %s\n' "$cmd" "$b" "${rounds} rounds" "reference (derived budget)"
            [ "${rounds:-0}" -eq 1 ] || { echo "  expected the derived budget to flush once"; fail=1; }
            continue
        fi
        bad=""
        for f in groups groupMap skipped_kmers; do
            cmp -s "$ref/$f" "$d/$f" || bad="$bad $f"
        done
        verdict=identical
        [ -n "$bad" ] && { verdict="DIFFER:$bad"; fail=1; }
        [ "${rounds:-0}" -gt 1 ] || { verdict="$verdict (NO MULTI-ROUND)"; fail=1; }
        printf '%-16s %-8s %-12s %s\n' "$cmd" "$b" "${rounds} rounds" "$verdict"
    done
done

echo
[ "$fail" -eq 0 ] && echo "RESULT: the flush schedule does not reach the output" || echo "RESULT: FAILED"
exit $fail
