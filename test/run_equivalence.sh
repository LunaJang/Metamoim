#!/bin/bash
# metamoim against metabuli on the same fixture.
#
# A plain cross-diff is not enough on its own: create-common-kmer-list writes three
# files that are not reproducible by the same binary either. So metabuli is run twice
# and the files that disagree with themselves become the allowed set; metamoim fails on
# any file outside it.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
METAMOIM=${METAMOIM:-$HERE/../build/src/metamoim}
METABULI=${METABULI:-$HOME/src/Metabuli_work/build_64680ee4/src/metabuli}
WORK=${WORK:-$HERE/work}
FIXTURE=$HERE/fixture

THREADS=${THREADS:-8}
PARTITIONS=${PARTITIONS:-16}

FILES="
ckl/diffIdx
ckl/info
ckl/split
ckl/taxID_list
ckl/kmer_params
ckl/taxonomyDB
ckl/db.parameters
taxonomy/names.dmp
taxonomy/nodes.dmp
taxonomy/taxid.accession2taxid
group/groups
group/groupMap
group/skipped_kmers
cap/groups
cap/groupMap
cap/skipped_kmers
easy/groups
easy/groupMap
easy/skipped_kmers
apply/groupRep
apply/updated_classifications.tsv
apply/updated_report.tsv
apply_easy/groupRep
apply_easy/updated_classifications.tsv
apply_easy/updated_report.tsv
"

for b in "$METAMOIM" "$METABULI"; do
    [ -x "$b" ] || { echo "no binary at $b" >&2; exit 1; }
done
[ -d "$FIXTURE" ] || { echo "no fixture; run make_fixture.py <dir> first" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"

run_one() {  # <tag> <binary>
    local tag=$1 bin=$2 d=$WORK/$1
    mkdir -p "$d/ckl" "$d/group" "$d/cap" "$d/easy" "$d/apply" "$d/apply_easy"
    # --gtdb 1 rewrites names.dmp where it stands, so each run gets its own taxonomy.
    cp -r "$FIXTURE/taxonomy" "$d/taxonomy"

    "$bin" create-common-kmer-list --gtdb 1 --threads "$THREADS" --cds-info x \
        --syncmer 1 --smer-len 5 --kmer-format 5 \
        "$d/ckl" "$FIXTURE/fasta_list.txt" "$d/taxonomy/taxid.map" "$d/taxonomy" \
        > "$d/ckl.log" 2>&1 || { echo "[$tag] create-common-kmer-list failed" >&2; return 1; }

    "$bin" grouping --threads "$THREADS" --partitions "$PARTITIONS" \
        "$FIXTURE/reads/R1.fq" "$FIXTURE/reads/R2.fq" "$d/ckl" "$d/group" \
        > "$d/group.log" 2>&1 || { echo "[$tag] grouping failed" >&2; return 1; }

    # The auto cap keeps every k-mer of a fixture this small, so one arm sets the cap by
    # hand to make the skip path write something.
    "$bin" grouping --threads "$THREADS" --partitions "$PARTITIONS" --max-kmer-reads 30 \
        "$FIXTURE/reads/R1.fq" "$FIXTURE/reads/R2.fq" "$d/ckl" "$d/cap" \
        > "$d/cap.log" 2>&1 || { echo "[$tag] grouping (capped) failed" >&2; return 1; }

    "$bin" easy-grouping --threads "$THREADS" --partitions "$PARTITIONS" \
        "$FIXTURE/reads/R1.fq" "$FIXTURE/reads/R2.fq" "$d/ckl" "$d/easy" \
        > "$d/easy.log" 2>&1 || { echo "[$tag] easy-grouping failed" >&2; return 1; }

    "$bin" apply-group --threads "$THREADS" \
        "$d/group/groups" "$d/group/groupMap" "$d/taxonomy" \
        "$FIXTURE/classification.tsv" "$d/apply" \
        > "$d/apply.log" 2>&1 || { echo "[$tag] apply-group failed" >&2; return 1; }

    "$bin" apply-group --threads "$THREADS" \
        "$d/easy/groups" "$d/easy/groupMap" "$d/taxonomy" \
        "$FIXTURE/classification.tsv" "$d/apply_easy" \
        > "$d/apply_easy.log" 2>&1 || { echo "[$tag] apply-group (star) failed" >&2; return 1; }
}

echo "metamoim : $METAMOIM"
echo "metabuli : $METABULI"
echo "threads $THREADS, partitions $PARTITIONS"
echo
echo "=== running: metabuli twice, metamoim once ==="
run_one metabuli_a "$METABULI" || exit 1
run_one metabuli_b "$METABULI" || exit 1
run_one metamoim  "$METAMOIM"  || exit 1

A=$WORK/metabuli_a
B=$WORK/metabuli_b
M=$WORK/metamoim

fail=0
unstable=0
echo
printf '%-42s %-14s %s\n' FILE "metabuli x2" "metamoim vs metabuli"
printf '%-42s %-14s %s\n' "----" "-----------" "--------------------"
for f in $FILES; do
    if [ ! -f "$A/$f" ] || [ ! -f "$M/$f" ]; then
        printf '%-42s %-14s %s\n' "$f" "-" "MISSING"; fail=1; continue
    fi
    if cmp -s "$A/$f" "$B/$f"; then self=stable; else self=UNSTABLE; unstable=$((unstable+1)); fi
    if cmp -s "$A/$f" "$M/$f"; then cross=identical
    elif [ "$f" = ckl/taxonomyDB ] \
         && python3 "$HERE/check_taxonomydb.py" "$A/$f" "$M/$f" > /dev/null; then
        cross="padding only (allowed)"
    elif [ "$self" = UNSTABLE ];  then cross="differs (allowed)"
    else cross=DIFFER; fail=1; fi
    printf '%-42s %-14s %s\n' "$f" "$self" "$cross"
done

echo
if [ "$unstable" -gt 0 ]; then
    echo "$unstable file(s) are not reproducible by metabuli itself. What differs:"
    for f in $FILES; do
        cmp -s "$A/$f" "$B/$f" && continue
        echo "  --- $f"
        if [ "$f" = ckl/db.parameters ]; then
            diff "$A/$f" "$B/$f" | sed 's/^/      /'
        elif cmp -s <(sort "$A/$f" 2>/dev/null) <(sort "$B/$f" 2>/dev/null); then
            echo "      same lines, different order"
        else
            echo "      $(cmp -l "$A/$f" "$B/$f" | wc -l) byte(s) of $(stat -c%s "$A/$f") differ"
        fi
    done
fi

if ! cmp -s "$A/ckl/taxonomyDB" "$M/ckl/taxonomyDB"; then
    echo
    echo "ckl/taxonomyDB, metamoim against metabuli:"
    python3 "$HERE/check_taxonomydb.py" "$A/ckl/taxonomyDB" "$M/ckl/taxonomyDB" \
        | sed 's/^/  /'
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: metamoim differs from metabuli on no file that carries a result."
else
    echo "RESULT: FAILED"
fi
exit $fail
