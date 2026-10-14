# Sourced, not run. One function that takes a fixture through every command, so the
# golden check, the metabuli check and the grade check all measure the same thing.

load_fixture_conf() {  # <fixture>
    GTDB=1
    ACC2TAXID=taxonomy/taxid.map
    GRADE=0
    GRADE_ANSWER=
    GRADE_TYPE=gtdb
    [ -f "$1/fixture.conf" ] && . "$1/fixture.conf"
}

run_pipeline() {  # <binary> <fixture> <outdir> [threads] [partitions]
    local bin=$1 fixture=$2 d=$3 threads=${4:-8} partitions=${5:-16}
    mkdir -p "$d/ckl" "$d/group" "$d/cap" "$d/easy" "$d/apply" "$d/apply_easy"
    cp -r "$fixture/taxonomy" "$d/taxonomy"

    local acc2taxid
    case $ACC2TAXID in
        taxonomy/*) acc2taxid=$d/$ACC2TAXID ;;
        *)          cp "$fixture/$ACC2TAXID" "$d/"
                    acc2taxid=$d/$(basename "$ACC2TAXID") ;;
    esac
    # create-common-kmer-list drops an .unmapped file beside the fasta list, so it reads
    # the run's own copy and leaves the fixture alone.
    cp "$fixture/fasta_list.txt" "$d/fasta_list.txt"

    "$bin" create-common-kmer-list --gtdb "$GTDB" --threads "$threads" --cds-info x \
        --syncmer 1 --smer-len 5 --kmer-format 5 \
        "$d/ckl" "$d/fasta_list.txt" "$acc2taxid" "$d/taxonomy" \
        > "$d/ckl.log" 2>&1 || { echo "create-common-kmer-list failed: $d" >&2; return 1; }

    "$bin" grouping --threads "$threads" --partitions "$partitions" \
        "$fixture/reads/R1.fq" "$fixture/reads/R2.fq" "$d/ckl" "$d/group" \
        > "$d/group.log" 2>&1 || { echo "grouping failed: $d" >&2; return 1; }

    # The derived cap keeps every k-mer of a fixture this small, so one arm sets it by hand
    # to make the skip path write something.
    "$bin" grouping --threads "$threads" --partitions "$partitions" --max-kmer-reads 30 \
        "$fixture/reads/R1.fq" "$fixture/reads/R2.fq" "$d/ckl" "$d/cap" \
        > "$d/cap.log" 2>&1 || { echo "grouping (capped) failed: $d" >&2; return 1; }

    "$bin" easy-grouping --threads "$threads" --partitions "$partitions" \
        "$fixture/reads/R1.fq" "$fixture/reads/R2.fq" "$d/ckl" "$d/easy" \
        > "$d/easy.log" 2>&1 || { echo "easy-grouping failed: $d" >&2; return 1; }

    "$bin" apply-group --threads "$threads" \
        "$d/group/groups" "$d/group/groupMap" "$d/taxonomy" \
        "$fixture/classification.tsv" "$d/apply" \
        > "$d/apply.log" 2>&1 || { echo "apply-group failed: $d" >&2; return 1; }

    "$bin" apply-group --threads "$threads" \
        "$d/easy/groups" "$d/easy/groupMap" "$d/taxonomy" \
        "$fixture/classification.tsv" "$d/apply_easy" \
        > "$d/apply_easy.log" 2>&1 || { echo "apply-group (star) failed: $d" >&2; return 1; }
}

# Every output a result depends on. Not here: the logs, which carry timings and the
# binary's commit; ckl/db.parameters, whose Creation_date is today's date; and
# taxonomy/taxid.accession2taxid, which only --gtdb 1 produces.
PIPELINE_OUTPUTS="
ckl/diffIdx
ckl/info
ckl/split
ckl/taxID_list
ckl/kmer_params
ckl/taxonomyDB
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
