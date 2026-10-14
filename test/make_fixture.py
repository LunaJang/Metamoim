#!/usr/bin/env python3
"""Build the synthetic fixture the equivalence check runs on.

Deterministic: one seed, no clock, no external tool. Running it twice gives
byte-identical files, which is what lets the two binaries be compared at all.
"""

import argparse
import os
import random

SEED = 20261014
BASES = "ACGT"

GENOME_LEN = 30000
CONSERVED_LEN = 1500
GENUS_BLOCK_LEN = 1500
STRAIN_DIVERGENCE = 0.005

COVERAGE = 15
READ_LEN = 150
FRAG_MEAN = 450
FRAG_SD = 40
ERROR_RATE = 0.002

CLASSIFIED_SHARE = 0.55
WRONG_SHARE = 0.03

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


def mutate(rng, s, rate):
    out = list(s)
    for i in range(len(out)):
        if rng.random() < rate:
            out[i] = rng.choice([b for b in BASES if b != out[i]])
    return "".join(out)


def revcomp(s):
    return s.translate(str.maketrans("ACGTN", "TGCAN"))[::-1]


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


def simulate(rng, acc, genome):
    pairs = round(len(genome) * COVERAGE / (2 * READ_LEN))
    out = []
    for i in range(pairs):
        frag = max(2 * READ_LEN, int(rng.gauss(FRAG_MEAN, FRAG_SD)))
        frag = min(frag, len(genome))
        start = rng.randrange(0, len(genome) - frag + 1)
        f = genome[start:start + frag]
        r1 = mutate(rng, f[:READ_LEN], ERROR_RATE)
        r2 = mutate(rng, revcomp(f)[:READ_LEN], ERROR_RATE)
        out.append(("%s_%05d" % (acc, i), r1, r2))
    return out


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

    rdir = os.path.join(out, "reads")
    os.makedirs(rdir, exist_ok=True)
    qual = "I" * READ_LEN
    reads = []
    for acc, _, species, _ in ASSEMBLIES:
        for name, r1, r2 in simulate(rng, acc, genomes[acc]):
            reads.append((name, r1, r2, species))
    with open(os.path.join(rdir, "R1.fq"), "w") as f1, \
         open(os.path.join(rdir, "R2.fq"), "w") as f2:
        for name, r1, r2, _ in reads:
            f1.write("@%s\n%s\n+\n%s\n" % (name, r1, qual))
            f2.write("@%s\n%s\n+\n%s\n" % (name, r2, qual))

    # A classification table in Metabuli's column order, so apply-group runs at its
    # defaults: 1 classified flag, 2 read id, 3 taxid, 4 query length, 5 score.
    species_ids = sorted({s for _, _, s, _ in ASSEMBLIES})
    with open(os.path.join(out, "classification.tsv"), "w") as f:
        for name, r1, r2, species in reads:
            roll = rng.random()
            if roll >= CLASSIFIED_SHARE:
                f.write("0\t%s\t0\t%d\t0.000\t no rank\t\n" % (name, len(r1) + len(r2)))
                continue
            if roll < WRONG_SHARE:
                taxid = rng.choice([s for s in species_ids if s != species])
            else:
                taxid = species
            score = round(0.50 + rng.random() * 0.50, 3)
            f.write("1\t%s\t%d\t%d\t%.3f\tspecies\t\n"
                    % (name, taxid, len(r1) + len(r2), score))

    with open(os.path.join(out, "answer.tsv"), "w") as f:
        for name, _, _, species in reads:
            f.write("%s\t%d\n" % (name, species))

    print("genomes      %d x %d bp" % (len(ASSEMBLIES), GENOME_LEN))
    print("read pairs   %d" % len(reads))
    print("fixture      %s" % out)


if __name__ == "__main__":
    main()
