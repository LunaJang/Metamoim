#!/usr/bin/env python3
"""Build the synthetic fixture the equivalence check runs on.

Deterministic: one seed, no clock, no external tool. Running it twice gives
byte-identical files, which is what lets the two binaries be compared at all.
"""

import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate
from simulate import BASES, mutate

SEED = 20261014

GENOME_LEN = 30000
CONSERVED_LEN = 1500
GENUS_BLOCK_LEN = 1500
STRAIN_DIVERGENCE = 0.005

COVERAGE = 15

# (assembly accession, assembly taxid, species taxid, genus taxid)
ASSEMBLIES = [
    ("GCF_000000001.1", 300001, 200000, 100000),
    ("GCF_000000002.1", 300002, 200000, 100000),
    ("GCF_000000003.1", 300003, 200001, 100000),
    ("GCF_000000004.1", 300004, 200001, 100000),
    ("GCF_000000005.1", 300005, 200002, 100001),
    ("GCF_000000006.1", 300006, 200002, 100001),
    ("GCF_000000007.1", 300007, 200003, 100001),
    ("GCF_000000008.1", 300008, 200003, 100001),
]

NODES = [
    (1, 1, "no rank"),
    (131567, 1, "no rank"),
    (2, 131567, "superkingdom"),
    (10, 2, "phylum"),
    (100, 10, "class"),
    (1000, 100, "order"),
    (10000, 1000, "family"),
    (100000, 10000, "genus"),
    (100001, 10000, "genus"),
    (200000, 100000, "species"),
    (200001, 100000, "species"),
    (200002, 100001, "species"),
    (200003, 100001, "species"),
]

NAMES = {
    1: "root",
    131567: "cellular organisms",
    2: "Bacteria",
    10: "Testimicrota",
    100: "Testimicrotia",
    1000: "Testimicrotales",
    10000: "Testimicrotaceae",
    100000: "Alphatestus",
    100001: "Betatestus",
    200000: "Alphatestus primus",
    200001: "Alphatestus secundus",
    200002: "Betatestus primus",
    200003: "Betatestus secundus",
}


def seq(rng, n):
    return "".join(rng.choice(BASES) for _ in range(n))


def build_genomes(rng):
    """Every assembly carries the same conserved block and its genus's block, so the
    common k-mer list has something to find and the cap has something to cap."""
    conserved = seq(rng, CONSERVED_LEN)
    genus_block = {100000: seq(rng, GENUS_BLOCK_LEN), 100001: seq(rng, GENUS_BLOCK_LEN)}

    unique_len = GENOME_LEN - CONSERVED_LEN - GENUS_BLOCK_LEN
    backbone = {}
    for _, _, species, _ in ASSEMBLIES:
        if species not in backbone:
            backbone[species] = seq(rng, unique_len)

    genomes = {}
    for acc, _, species, genus in ASSEMBLIES:
        u = mutate(rng, backbone[species], STRAIN_DIVERGENCE)
        a, b = unique_len // 3, 2 * (unique_len // 3)
        genomes[acc] = u[:a] + conserved + u[a:b] + genus_block[genus] + u[b:]
    return genomes


def write_taxonomy(d):
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "nodes.dmp"), "w") as f:
        for tid, parent, rank in NODES:
            f.write("%d\t|\t%d\t|\t%s\t|\t-\t|\n" % (tid, parent, rank))
        for _, tid, species, _ in ASSEMBLIES:
            f.write("%d\t|\t%d\t|\tassembly\t|\t-\t|\n" % (tid, species))
    with open(os.path.join(d, "names.dmp"), "w") as f:
        for tid, name in sorted(NAMES.items()):
            f.write("%d\t|\t%s\t|\t\t|\tscientific name\t|\n" % (tid, name))
        # gtdb-taxdump names an assembly leaf by the digits of its accession, which is
        # what editNames looks the taxid.map up by.
        for acc, tid, _, _ in ASSEMBLIES:
            f.write("%d\t|\t%s\t|\t\t|\tscientific name\t|\n"
                    % (tid, acc.split("_")[1].split(".")[0]))
    open(os.path.join(d, "merged.dmp"), "w").close()
    with open(os.path.join(d, "taxid.map"), "w") as f:
        for acc, tid, _, _ in ASSEMBLIES:
            f.write("%s\t%d\n" % (acc, tid))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    args = ap.parse_args()
    out = os.path.abspath(args.outdir)

    rng = random.Random(SEED)
    genomes = build_genomes(rng)

    gdir = os.path.join(out, "genomes")
    os.makedirs(gdir, exist_ok=True)
    for acc, _, _, _ in ASSEMBLIES:
        path = os.path.join(gdir, "%s_genomic.fna" % acc)
        with open(path, "w") as f:
            f.write(">%s_contig1 %s\n" % (acc, acc))
            g = genomes[acc]
            for i in range(0, len(g), 70):
                f.write(g[i:i + 70] + "\n")
    with open(os.path.join(out, "fasta_list.txt"), "w") as f:
        for acc, _, _, _ in ASSEMBLIES:
            f.write(os.path.join(gdir, "%s_genomic.fna" % acc) + "\n")

    write_taxonomy(os.path.join(out, "taxonomy"))

    reads, truth = [], {}
    for acc, _, species, _ in ASSEMBLIES:
        for r in simulate.simulate(rng, acc, genomes[acc], COVERAGE):
            reads.append(r)
            truth[r[0]] = species
    simulate.write_reads(os.path.join(out, "reads"), reads)
    simulate.write_classification(os.path.join(out, "classification.tsv"), rng, reads,
                                  truth, sorted({s for _, _, s, _ in ASSEMBLIES}))
    simulate.write_answer(os.path.join(out, "answer.tsv"), reads, truth)

    with open(os.path.join(out, "fixture.conf"), "w") as f:
        f.write("GTDB=1\nACC2TAXID=taxonomy/taxid.map\n")

    print("genomes      %d x %d bp" % (len(ASSEMBLIES), GENOME_LEN))
    print("read pairs   %d" % len(reads))
    print("fixture      %s" % out)


if __name__ == "__main__":
    main()
