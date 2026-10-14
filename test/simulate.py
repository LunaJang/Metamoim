"""Seeded read simulator shared by the two fixture builders.

No clock and no OS entropy, so a fixture rebuilt anywhere is byte for byte the one the
comparison was run on.
"""

import os
import random

BASES = "ACGT"
READ_LEN = 150
FRAG_MEAN = 450
FRAG_SD = 40
ERROR_RATE = 0.002

CLASSIFIED_SHARE = 0.55
WRONG_SHARE = 0.03


def mutate(rng, s, rate):
    out = list(s)
    for i in range(len(out)):
        if out[i] in BASES and rng.random() < rate:
            out[i] = rng.choice([b for b in BASES if b != out[i]])
    return "".join(out)


def revcomp(s):
    return s.translate(str.maketrans("ACGTNacgtn", "TGCANtgcan"))[::-1]


def simulate(rng, name, genome, coverage):
    pairs = round(len(genome) * coverage / (2 * READ_LEN))
    out = []
    for i in range(pairs):
        frag = max(2 * READ_LEN, int(rng.gauss(FRAG_MEAN, FRAG_SD)))
        frag = min(frag, len(genome))
        start = rng.randrange(0, len(genome) - frag + 1)
        f = genome[start:start + frag]
        out.append(("%s_%05d" % (name, i),
                    mutate(rng, f[:READ_LEN], ERROR_RATE),
                    mutate(rng, revcomp(f)[:READ_LEN], ERROR_RATE)))
    return out


def write_fasta(path, header, seq, width=70):
    with open(path, "w") as f:
        f.write(">%s\n" % header)
        for i in range(0, len(seq), width):
            f.write(seq[i:i + width] + "\n")


def write_reads(outdir, reads):
    os.makedirs(outdir, exist_ok=True)
    qual = "I" * READ_LEN
    with open(os.path.join(outdir, "R1.fq"), "w") as f1, \
         open(os.path.join(outdir, "R2.fq"), "w") as f2:
        for name, r1, r2 in reads:
            f1.write("@%s\n%s\n+\n%s\n" % (name, r1, qual))
            f2.write("@%s\n%s\n+\n%s\n" % (name, r2, qual))


def write_classification(path, rng, reads, truth, all_taxids):
    """Metabuli's column order, so apply-group runs at its defaults: 1 classified flag,
    2 read id, 3 taxid, 4 query length, 5 score. Some reads are left unlabelled for
    propagation to fill and a few are labelled wrong for the vote to outweigh."""
    with open(path, "w") as f:
        for name, r1, r2 in reads:
            roll = rng.random()
            n = len(r1) + len(r2)
            if roll >= CLASSIFIED_SHARE:
                f.write("0\t%s\t0\t%d\t0.000\t no rank\t\n" % (name, n))
                continue
            t = truth[name]
            if roll < WRONG_SHARE:
                t = rng.choice([x for x in all_taxids if x != t])
            f.write("1\t%s\t%d\t%d\t%.3f\tspecies\t\n"
                    % (name, t, n, round(0.50 + rng.random() * 0.50, 3)))


def write_answer(path, reads, truth):
    with open(path, "w") as f:
        for name, _, _ in reads:
            f.write("%s\t%d\n" % (name, truth[name]))
