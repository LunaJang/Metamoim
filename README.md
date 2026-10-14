# Metamoum

Metamoum groups metagenomic reads by the k-mers they share, and propagates a group's label to
its unlabelled members.

It is the read-grouping half of [Metabuli](https://github.com/steineggerlab/Metabuli), split out
so that it builds and runs on its own. The grouping code is unchanged: same algorithm, same
parameters, same output files.

## Where it comes from

Split from Metabuli at commit `64680ee4` on 2026-10-14. Every file that takes part in producing
a result was copied byte for byte; what is new here is the command table, the program entry
point and the CMake wiring. The classification, database-building, UniRef and benchmark commands
were left behind.

`VERIFICATION.md` records the evidence: a file-by-file `cmp` against Metabuli, the pinned
submodule commits, and a comparison of the two builds' compiler warnings.

## Commands

| Command | |
|---|---|
| `grouping` | Build read groups from shared k-mers (full C(m,2) clique per k-mer) |
| `easy-grouping` | Same, with a centre-star edge set — faster and lighter, lower graph precision |
| `apply-group` | Give a group's representative taxon to its members that have no label |
| `create-common-kmer-list` | Build the common k-mer database the two grouping commands need |
| `count-common-kmers` | Report what a common k-mer database holds, by taxonomic rank |
| `gradeGroup` | CAMI purity / recall / F1 per rank |
| `gradeGroupByCoverage` | The same, split by per-genome coverage |
| `gradeStrain` | Score against genome ids rather than taxonomy |

The last five are expert commands and are hidden from `metamoum -h`, as they are in Metabuli.

## Build

Requires CMake 3.15+, a C++17 compiler, OpenMP and zlib.

```sh
git clone --recursive <this repository> Metamoum
cd Metamoum
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

The binary lands at `build/src/metamoum`; `cmake --install build` puts it in `bin/`.

If the repository was cloned without `--recursive`:

```sh
git submodule update --init --recursive
```

`lib/mmseqs` and `lib/fasta_validator` are submodules pinned to the same commits Metabuli uses.
`lib/prodigal`, `lib/fastq_utils`, `lib/json` and `lib/yxml` are vendored in the tree, also as
Metabuli does it.

## Usage

```sh
# 1. a common k-mer list, once per reference set
metamoum create-common-kmer-list <db dir> <FASTA list> <accession2taxid> <taxonomy dir>

# 2. group the reads
metamoum grouping <read_1.fq> <read_2.fq> <common k-mer db> <out dir>

# 3. propagate labels onto a read-by-read classification
metamoum apply-group <out dir>/groups <out dir>/groupMap <taxonomy dir> <classification.tsv> <out dir>
```

`grouping` writes `groups` (one line per group: id then members), `groupMap` (one line per read:
id then group, `0` when ungrouped) and `skipped_kmers` (k-mers dropped for being shared by too
many reads). Read ids are 1-based and follow the order of the input file.

`apply-group` writes `groupRep`, `updated_classifications.tsv` and `updated_report.tsv`.
It reads a classifier's read-by-read output; `--readid-col`, `--taxid-col` and `--score-col` say
where the fields are (one-based), and `--kraken2` reads Kraken2's LCA mapping as a confidence
score.

Run `metamoum <command> -h` for the full parameter list — every parameter carries the reasoning
and the measurements behind its default.

## License

GPL-3.0, inherited from Metabuli. See `LICENSE`.
