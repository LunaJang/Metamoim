#!/bin/bash
# What a run means, in a few dozen lines. The sha256 manifest beside this catches any
# change at all; this says what the change was, which is what a reviewer needs.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pipeline.sh"

RUN=${1:?usage: summarize.sh <rundir> <fixture>}
FIXTURE=${2:?usage: summarize.sh <rundir> <fixture>}
BIN=${BIN:-$HERE/../build/src/metamoim}
load_fixture_conf "$FIXTURE"

n()  { wc -l < "$1" | tr -d ' '; }
log() { grep -oE "$2" "$RUN/$1" | head -1; }

echo "# reads"
echo "read pairs                $(( $(n "$FIXTURE/reads/R1.fq") / 4 ))"
echo "labelled before           $(awk -F'\t' '$1==1' "$FIXTURE/classification.tsv" | wc -l | tr -d ' ')"

echo
echo "# common k-mer list"
echo "k-mers kept               $(log ckl.log 'Total k-mer count   : [0-9]+' | grep -oE '[0-9]+$')"
echo "taxa                      $(n "$RUN/ckl/taxID_list")"

echo
echo "# grouping"
for arm in group cap easy; do
    # A groups line is the group id then its members, so the members are the fields that
    # are not the first of a line.
    printf '%-14s groups %-8s grouped reads %-9s %s\n' "$arm" \
        "$(n "$RUN/$arm/groups")" \
        "$(awk '{t += NF - 1} END {print t+0}' "$RUN/$arm/groups")" \
        "$(log "$arm.log" 'Core threshold: [0-9]+ \(overlap ratio [0-9.]+ x [0-9.]+ k-mers/read\)')"
done
echo "common k-mer hits removed $(log group.log '\([0-9]+ matches found\)' | grep -oE '[0-9]+')"
echo "k-mers skipped, auto cap  $(log group.log '[0-9]+ k-mers skipped' | grep -oE '^[0-9]+')"
echo "k-mers skipped, cap 30    $(log cap.log '[0-9]+ k-mers skipped' | grep -oE '^[0-9]+')"

echo
echo "# propagation"
for arm in apply apply_easy; do
    printf '%-14s labelled after %-9s groups given a label %s\n' "$arm" \
        "$(awk -F'\t' '$1==1' "$RUN/$arm/updated_classifications.tsv" | wc -l | tr -d ' ')" \
        "$(n "$RUN/$arm/groupRep")"
done

[ "$GRADE" = 1 ] || { echo; echo "# grade"; echo "not graded: this fixture's read names carry no assembly accession"; exit 0; }

echo
echo "# grade, against the answer sheet"
g=$RUN/grade
mkdir -p "$g"
for arm in group easy; do
    echo "$RUN/$arm/groups"            > "$g/$arm.groups.list"
    echo "$RUN/$arm/groupMap"          > "$g/$arm.map.list"
    echo "$FIXTURE/$GRADE_ANSWER"      > "$g/$arm.answer.list"
    echo "$FIXTURE/query_names.txt"    > "$g/$arm.names.list"
    "$BIN" gradeGroup --threads 1 --test-type "$GRADE_TYPE" \
        "$g/$arm.groups.list" "$g/$arm.map.list" "$g/$arm.answer.list" \
        "$g/$arm.names.list" "$FIXTURE/taxonomy" \
        > "$g/$arm.out" 2>&1 || { echo "gradeGroup failed on $arm"; continue; }
    echo "## $arm   purity / recall / F1"
    awk 'BEGIN{OFS="\t"} /^(class|order|family|genus|species)\t/ {printf "%-10s %s %s %s\n", $1, $2, $3, $4}' \
        "$g/$arm.out"
done
