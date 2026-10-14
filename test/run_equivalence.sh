#!/bin/bash
# metamoim against metabuli 64680ee4, and each against itself.
#
# Not the check that runs on every push -- run_golden.sh is. This one answers a different
# question: is the golden still the same thing Metabuli produced, or has it drifted into
# being whatever we happened to write last? Run it when the golden moves.
#
# Each binary runs twice, because metabuli writes files it does not reproduce itself and
# that is shown rather than assumed.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pipeline.sh"

METAMOIM=${METAMOIM:-$HERE/../build/src/metamoim}
METABULI=${METABULI:-$HOME/src/Metabuli_work/build_64680ee4/src/metabuli}
WORK=${WORK:-$HERE/work}
FIXTURE=${FIXTURE:-$HERE/fixture}
THREADS=${THREADS:-8}
PARTITIONS=${PARTITIONS:-16}

for b in "$METAMOIM" "$METABULI"; do
    [ -x "$b" ] || { echo "no binary at $b" >&2; exit 1; }
done
[ -d "$FIXTURE" ] || { echo "no fixture at $FIXTURE" >&2; exit 1; }

load_fixture_conf "$FIXTURE"

FILES="$PIPELINE_OUTPUTS
ckl/db.parameters
taxonomy/names.dmp
taxonomy/nodes.dmp"
[ "$GTDB" = 1 ] && FILES="$FILES
taxonomy/taxid.accession2taxid"

# Files metamoim writes differently on purpose, and how each difference is checked.
known() {
    case $1 in
        ckl/taxID_list|taxonomy/taxid.accession2taxid) echo same_set ;;
        ckl/db.parameters)                             echo params ;;
        ckl/taxonomyDB)                                echo padding ;;
        *)                                             echo "" ;;
    esac
}

rm -rf "$WORK"
mkdir -p "$WORK"

echo "metamoim : $METAMOIM"
echo "metabuli : $METABULI"
echo "fixture  : $FIXTURE"
echo
echo "=== running each binary twice ==="
for tag in metabuli_a metabuli_b metamoim_a metamoim_b; do
    case $tag in metabuli_*) bin=$METABULI ;; *) bin=$METAMOIM ;; esac
    run_pipeline "$bin" "$FIXTURE" "$WORK/$tag" "$THREADS" "$PARTITIONS" || exit 1
done

A=$WORK/metabuli_a; B=$WORK/metabuli_b
M=$WORK/metamoim_a; N=$WORK/metamoim_b

fail=0
echo
printf '%-40s %-13s %-13s %s\n' FILE "metabuli x2" "metamoim x2" "metamoim vs metabuli"
printf '%-40s %-13s %-13s %s\n' "----" "-----------" "-----------" "--------------------"
for f in $FILES; do
    for side in "$A" "$B" "$M" "$N"; do
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
                if [ -z "$(diff "$A/$f" "$M/$f" | grep '^[<>]' \
                           | grep -vE 'DB_name|Creation_date|commit used to create the DB')" ]
                then cross="name/date only (intended)"
                else cross=DIFFER; fail=1; fi ;;
            padding)
                if python3 "$HERE/check_taxonomydb.py" "$A/$f" "$M/$f" > /dev/null
                then cross="padding zeroed (intended)"
                else cross=DIFFER; fail=1; fi ;;
            *)  cross=DIFFER; fail=1 ;;
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
