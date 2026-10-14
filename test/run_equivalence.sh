#!/bin/bash
# metamoim against metabuli 64680ee4 on the same fixture, and each against itself.
#
# Two questions, not one:
#   1. is metamoim reproducible?   -- run it twice, every file must match
#   2. does it agree with metabuli? -- every file must match except the four that
#      metamoim deliberately writes differently, listed in KNOWN below
# metabuli is run twice as well, so its own non-reproducibility is shown rather than
# assumed.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
METAMOIM=${METAMOIM:-$HERE/../build/src/metamoim}
METABULI=${METABULI:-$HOME/src/Metabuli_work/build_64680ee4/src/metabuli}
WORK=${WORK:-$HERE/work}
FIXTURE=${FIXTURE:-$HERE/fixture}

THREADS=${THREADS:-8}
PARTITIONS=${PARTITIONS:-16}

# Each fixture says how its taxonomy is given. The synthetic one mimics gtdb-taxdump
# (--gtdb 1, a taxid.map that create-common-kmer-list turns into an accession table);
# the real one hands over an accession table already, so nothing rewrites names.dmp.
GTDB=1
ACC2TAXID=taxonomy/taxid.map
[ -f "$FIXTURE/fixture.conf" ] && . "$FIXTURE/fixture.conf"

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

# Files metamoim writes differently on purpose, and how the difference is checked.
known() {
    case $1 in
        ckl/taxID_list|taxonomy/taxid.accession2taxid) echo same_set ;;
        ckl/db.parameters)                             echo params ;;
        ckl/taxonomyDB)                                echo padding ;;
        *)                                             echo "" ;;
    esac
}

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

    # Under --gtdb 1 the mapping is rewritten in place, so it has to be the run's own copy.
    local acc2taxid
    case $ACC2TAXID in
        taxonomy/*) acc2taxid=$d/$ACC2TAXID ;;
        *)          cp "$FIXTURE/$ACC2TAXID" "$d/"
                    acc2taxid=$d/$(basename "$ACC2TAXID") ;;
    esac

    "$bin" create-common-kmer-list --gtdb "$GTDB" --threads "$THREADS" --cds-info x \
        --syncmer 1 --smer-len 5 --kmer-format 5 \
        "$d/ckl" "$FIXTURE/fasta_list.txt" "$acc2taxid" "$d/taxonomy" \
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
echo "fixture  : $FIXTURE"
echo "threads $THREADS, partitions $PARTITIONS"
echo
echo "=== running each binary twice ==="
run_one metabuli_a "$METABULI" || exit 1
run_one metabuli_b "$METABULI" || exit 1
run_one metamoim_a "$METAMOIM" || exit 1
run_one metamoim_b "$METAMOIM" || exit 1

A=$WORK/metabuli_a
B=$WORK/metabuli_b
M=$WORK/metamoim_a
N=$WORK/metamoim_b

# Only --gtdb 1 writes this one: it is the table create-common-kmer-list derives.
[ "$GTDB" = 1 ] && FILES="$FILES
taxonomy/taxid.accession2taxid"

fail=0
echo
printf '%-40s %-13s %-13s %s\n' FILE "metabuli x2" "metamoim x2" "metamoim vs metabuli"
printf '%-40s %-13s %-13s %s\n' "----" "-----------" "-----------" "--------------------"
for f in $FILES; do
    for side in "$A" "$M" "$N" "$B"; do
        [ -f "$side/$f" ] || { printf '%-40s %s\n' "$f" "MISSING"; fail=1; continue 2; }
    done

    cmp -s "$A/$f" "$B/$f" && mbself=stable || mbself=unstable
    if cmp -s "$M/$f" "$N/$f"; then mmself=stable; else mmself=UNSTABLE; fail=1; fi

    if cmp -s "$A/$f" "$M/$f"; then
        cross=identical
    else
        case $(known "$f") in
            same_set)
                if cmp -s <(sort "$A/$f") <(sort "$M/$f"); then cross="sorted (intended)"
                else cross="DIFFERENT SET"; fail=1; fi ;;
            params)
                # Creation_date and the key naming the tool are allowed to differ, and
                # DB_name differs because metabuli randomises it.
                if [ -z "$(diff "$A/$f" "$M/$f" | grep '^[<>]' \
                           | grep -vE 'DB_name|Creation_date|commit used to create the DB')" ]
                then cross="name/date only (intended)"
                else cross=DIFFER; fail=1; fi ;;
            padding)
                if python3 "$HERE/check_taxonomydb.py" "$A/$f" "$M/$f" > /dev/null
                then cross="padding zeroed (intended)"
                else cross=DIFFER; fail=1; fi ;;
            *)
                cross=DIFFER; fail=1 ;;
        esac
    fi
    printf '%-40s %-13s %-13s %s\n' "$f" "$mbself" "$mmself" "$cross"
done

echo
echo "files metamoim writes differently, on purpose:"
for f in ckl/taxID_list taxonomy/taxid.accession2taxid ckl/db.parameters ckl/taxonomyDB; do
    [ -f "$M/$f" ] || continue
    echo "  --- $f"
    case $(known "$f") in
        same_set) echo "      metabuli order random, metamoim sorted; same $(wc -l < "$M/$f") lines" ;;
        params)   diff "$A/$f" "$M/$f" | sed 's/^/      /' ;;
        padding)  python3 "$HERE/check_taxonomydb.py" "$A/$f" "$M/$f" | sed 's/^/      /' ;;
    esac
done

echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: metamoim is reproducible, and agrees with metabuli everywhere the two"
    echo "        are meant to agree."
else
    echo "RESULT: FAILED"
fi
exit $fail
