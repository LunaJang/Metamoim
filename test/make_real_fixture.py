#!/usr/bin/env python3
"""Build the fixture whose sequence is real.

Six human coronavirus reference genomes, six distinct NCBI species in two genera. Their
conserved regions -- ORF1ab, the RdRp -- are the homology the common k-mer list is meant
to find, and they are the genome's own rather than a block this script pasted in. The
taxonomy is NCBI's, pruned to these lineages.

The reads are still simulated: there is no public read set that covers six species at a
known truth. What this fixture replaces is the sequence, which is where composition,
repeats and real cross-species homology live.

The sequence and the taxonomy are committed under test/data, so a run needs no network.
--refresh fetches them from NCBI again; the accessions are versioned and RefSeq does not
reissue a version, so a refresh should be a no-op.
"""

import argparse
import os
import random
import sys
import urllib.request
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate

SEED = 20261014
COVERAGE = 30
EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

# accession -> the NCBI taxon the sequence is, whose species ancestor the list separates
GENOMES = [
    ("NC_045512.2", 2697049, "SARS-CoV-2"),
    ("NC_019843.3", 1335626, "MERS-CoV"),
    ("NC_002645.1", 11137, "HCoV-229E"),
    ("NC_006213.1", 31631, "HCoV-OC43"),
    ("NC_005831.2", 277944, "HCoV-NL63"),
    ("NC_006577.2", 290028, "HCoV-HKU1"),
]


def fetch(url, path, refresh):
    if not refresh and os.path.exists(path) and os.path.getsize(path) > 0:
        return open(path, "rb").read()
    with urllib.request.urlopen(url, timeout=120) as r:
        data = r.read()
    with open(path, "wb") as f:
        f.write(data)
    return data


def read_fasta(text):
    out, name, buf = {}, None, []
    for line in text.splitlines():
        if line.startswith(">"):
            if name:
                out[name] = "".join(buf)
            name, buf = line[1:].split()[0], []
        else:
            buf.append(line.strip())
    if name:
        out[name] = "".join(buf)
    return out


def taxonomy(xml):
    """(nodes, names) pruned to the lineages of the requested taxa. Both are NCBI's own
    ids, ranks and scientific names; nothing here is invented."""
    nodes, names = {1: (1, "no rank")}, {1: "root"}
    for t in ET.fromstring(xml).findall("Taxon"):
        chain = [(lt.findtext("TaxId"), lt.findtext("Rank"), lt.findtext("ScientificName"))
                 for lt in t.find("LineageEx").findall("Taxon")]
        chain.append((t.findtext("TaxId"), t.findtext("Rank"), t.findtext("ScientificName")))
        parent = 1
        for tid, rank, name in chain:
            tid = int(tid)
            nodes.setdefault(tid, (parent, rank or "no rank"))
            names.setdefault(tid, name)
            parent = tid
    return nodes, names


def species_of(tid, nodes):
    while tid != 1:
        parent, rank = nodes[tid]
        if rank == "species":
            return tid
        tid = parent
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--refresh", action="store_true",
                    help="fetch the sequence and taxonomy from NCBI again")
    args = ap.parse_args()
    out = os.path.abspath(args.outdir)
    data = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
    os.makedirs(data, exist_ok=True)

    accs = ",".join(a for a, _, _ in GENOMES)
    taxids = ",".join(str(t) for _, t, _ in GENOMES)
    fa = fetch("%s?db=nuccore&id=%s&rettype=fasta&retmode=text" % (EUTILS, accs),
               os.path.join(data, "genomes.fna"), args.refresh).decode()
    tx = fetch("%s?db=taxonomy&id=%s&retmode=xml" % (EUTILS, taxids),
               os.path.join(data, "taxonomy.xml"), args.refresh).decode()

    seqs = read_fasta(fa)
    missing = [a for a, _, _ in GENOMES if a not in seqs]
    if missing:
        sys.exit("NCBI returned no sequence for: %s" % ", ".join(missing))

    nodes, names = taxonomy(tx)

    gdir = os.path.join(out, "genomes")
    os.makedirs(gdir, exist_ok=True)
    with open(os.path.join(out, "fasta_list.txt"), "w") as fl:
        for acc, _, label in GENOMES:
            path = os.path.join(gdir, "%s.fna" % acc)
            simulate.write_fasta(path, "%s %s" % (acc, label), seqs[acc])
            fl.write(path + "\n")

    tdir = os.path.join(out, "taxonomy")
    os.makedirs(tdir, exist_ok=True)
    with open(os.path.join(tdir, "nodes.dmp"), "w") as f:
        for tid in sorted(nodes):
            parent, rank = nodes[tid]
            f.write("%d\t|\t%d\t|\t%s\t|\t-\t|\n" % (tid, parent, rank))
    with open(os.path.join(tdir, "names.dmp"), "w") as f:
        for tid in sorted(names):
            f.write("%d\t|\t%s\t|\t\t|\tscientific name\t|\n" % (tid, names[tid]))
    open(os.path.join(tdir, "merged.dmp"), "w").close()

    # --gtdb 0: the mapping is given as it stands, so no step rewrites names.dmp and the
    # leaves keep NCBI's own taxa.
    with open(os.path.join(out, "acc2taxid.tsv"), "w") as f:
        f.write("accession\taccession.version\ttaxid\tgi\n")
        for acc, tid, _ in GENOMES:
            f.write("%s\t%s\t%d\t0\n" % (acc.split(".")[0], acc, tid))

    rng = random.Random(SEED)
    reads, truth = [], {}
    sp = {acc: species_of(tid, nodes) for acc, tid, _ in GENOMES}
    for acc, _, _ in GENOMES:
        for r in simulate.simulate(rng, acc, seqs[acc], COVERAGE):
            reads.append(r)
            truth[r[0]] = sp[acc]
    simulate.write_reads(os.path.join(out, "reads"), reads)
    simulate.write_classification(os.path.join(out, "classification.tsv"), rng, reads,
                                  truth, sorted(set(sp.values())))
    simulate.write_query_names(os.path.join(out, "query_names.txt"), reads)

    with open(os.path.join(out, "fixture.conf"), "w") as f:
        # GRADE=0: gradeGroup recovers a read's source from its name, and its gtdb mode
        # wants a GCF/GCA accession. These reads carry NC_ accessions, and renaming them to
        # look like assemblies would be inventing data to satisfy a parser.
        f.write("GTDB=0\nACC2TAXID=acc2taxid.tsv\nGRADE=0\n")

    print("genomes    %d real, %d distinct species, %d bp total"
          % (len(GENOMES), len(set(sp.values())), sum(len(seqs[a]) for a, _, _ in GENOMES)))
    print("read pairs %d" % len(reads))
    print("fixture    %s" % out)


if __name__ == "__main__":
    main()
