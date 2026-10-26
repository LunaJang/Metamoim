#include "NcbiTaxonomy.h"
#include "Parameters.h"
#include "LocalParameters.h"
#include "IndexCreator.h"

#include <string>
#include <iostream>
#include <regex>
#include <cstdint>
#include <array>

using namespace std;

// Everything below is in a named namespace, and `grade` is a one-line wrapper at the end.
//
// Without it this file and gradeGroup.cpp both declare a struct called CountAtRank, with
// different members, and both instantiate unordered_map<string, CountAtRank>. The two
// instantiations mangle to the same weak symbol, the linker keeps one, and whichever loses
// indexes its map with the other's layout: gradeGroup scored every rank zero on the test
// fixture the moment this file joined the binary. The structs are file-local in intent --
// giving them internal linkage is what that intent should always have looked like.
namespace grade_impl {

struct CountAtRank {
    int total;
    int FP;
    int TP;
    int FN;
    // Reads whose answer taxon does not resolve at this rank, so they are outside the score
    // rather than a hit or a miss. Counted because the answer sheet can legitimately be missing
    // reads -- CAMI3's is written .nohost, so every host read reaches here -- and a score over
    // an unstated subset of the sample is not interpretable.
    int noAnswer;
    float precision;
    float sensitivity;
    float f1;
    void calculate() {
        precision = (float)TP / (float)(TP + FP);
        sensitivity = (float)TP / (float)(total);
        f1 = 2 * precision * sensitivity / (precision + sensitivity);
    }
};

struct GradeResult{
    unordered_map<string, CountAtRank> countsAtRanks;
    string path;
    // Filled only under --score-hist: rank -> verdict (0 TP, 1 FP, 2 FN) -> bin counts.
    unordered_map<string, array<vector<uint64_t>, 3>> scoreHist;
};

struct Score2{
    Score2(int tf, std::string rank, float score) : tf(tf), rank(rank), score(score) { }
    int tf; // 1 = t, 2 = f
    std::string rank;
    float score;
};



char compareTaxonAtRank_CAMI(TaxID shot, TaxID target, const TaxonomyWrapper & ncbiTaxonomy, CountAtRank & count,
                             const string & rank);

char compareTaxonAtRank_CAMI_euk(TaxID shot, TaxID target, TaxonomyWrapper & ncbiTaxonomy, CountAtRank & count,
                                 const string & rank);

char compareTaxon_overclassification(TaxID shot, TaxID target, TaxonomyWrapper & ncbiTaxonomy, CountAtRank & count,
                                     const string & rank);

char compareTaxon_hivExclusion(TaxID shot, TaxID target, CountAtRank & count);

// Kraken2 writes an LCA mapping where the other classifiers write a score. This is the same
// function apply-group uses on the same field (GroupApplier.cpp): space separated taxon:count
// pairs, 'A' for k-mers holding an ambiguous nucleotide, '0' for k-mers queried that matched
// nothing, '|:|' between the mates. Q is every count except 'A', since those were never
// queried; N is the counts whose taxon lies in the clade rooted at the assigned one, so a read
// assigned to a genus scores on its species' hits too. Duplicated rather than shared because
// the two commands do not link against each other, and a histogram drawn with a different
// definition than the one the threshold will be applied with is worse than no histogram.
static float kraken2Confidence(const std::string & mapping,
                               TaxID assigned,
                               TaxonomyWrapper & taxonomy) {
    uint64_t queried = 0;
    uint64_t inClade = 0;
    size_t i = 0;
    const size_t n = mapping.size();
    while (i < n) {
        while (i < n && mapping[i] == ' ') { i++; }
        size_t end = i;
        while (end < n && mapping[end] != ' ') { end++; }
        if (end == i) { break; }
        const size_t colon = mapping.rfind(':', end - 1);
        if (colon == std::string::npos || colon < i) { i = end; continue; }
        const std::string key = mapping.substr(i, colon - i);
        const uint64_t count = strtoull(mapping.c_str() + colon + 1, nullptr, 10);
        i = end;
        if (key.empty() || key == "|") { continue; }
        if (key == "A") { continue; }
        queried += count;
        if (key == "0") { continue; }
        const TaxID hit = static_cast<TaxID>(strtol(key.c_str(), nullptr, 10));
        if (hit == assigned || (assigned != 0 && taxonomy.IsAncestor(assigned, hit))) {
            inClade += count;
        }
    }
    if (queried == 0) { return 0.0f; }
    return static_cast<float>(inClade) / static_cast<float>(queried);
}

// 1000 bins over [0, 1]. The score is a rate, three decimals is finer than any threshold
// anyone reads off a plot, and the whole table is 1000 x ranks x 3 lines whatever the sample
// size -- the per-read scores are hundreds of millions of lines and are never written.
static const int SCORE_BINS = 1000;

void setGradeDefault(LocalParameters & par){
    par.readIdCol = 1;
    par.taxidCol = 2;
    par.verbosity = 2;
    par.scoreCol = 0;
    par.histScoreCol = 0;
    par.histDenomCol = -1;
    par.scoreHist = "";
    par.kraken2Format = false;
    par.testRank = "";
    par.testType = "gtdb";
    par.skipSecondary = 0;
}

int grade(int argc, const char **argv, const Command &command) {

    LocalParameters &par = LocalParameters::getLocalInstance();
    setGradeDefault(par);
    par.parseParameters(argc, argv, command, false, Parameters::PARSE_ALLOW_EMPTY, 0);
    const string readClassificationFileList = par.filenames[0];
    const string mappingFileList = par.filenames[1];
    const string taxonomy = par.filenames[2];

    // No negative-value check on --readid-col / --taxid-col: their parameter regex is ^[0-9]+$,
    // so the argument parser rejects a negative before it reaches here. The bound that does need
    // checking is the upper one, against each line's field count, and that is done at the parse
    // site below where the count is known.

    // Parse ranks
    vector<string> ranks;
    if (!par.testRank.empty()) {
        ranks = Util::split(par.testRank, ",");
    } else {
        ranks = {"class", "order", "family", "genus", "species"};
    }

    // Parse print columns
    vector<string> printColumns;
    vector<size_t> printColumnsIdx;
    if (!par.printColumns.empty()) {
        printColumns = Util::split(par.printColumns, ",");
        // stoi
        for (const auto &printColumn : printColumns) {
            printColumnsIdx.push_back(stoi(printColumn));
        }
    }

    // Load Taxonomy
    string names = taxonomy + "/names.dmp";
    string nodes = taxonomy + "/nodes.dmp";
    string merged = taxonomy + "/merged.dmp";
    
    

    // Load mapping file names
    ifstream mappingFileListFile;
    mappingFileListFile.open(mappingFileList);
    string eachLine;
    vector<string> mappingFileNames;
    if (mappingFileListFile.is_open()) {
        while (getline(mappingFileListFile, eachLine)) {
            mappingFileNames.push_back(eachLine);
        }
    } else {
        cerr << "Cannot open file for mapping file list" << endl;
    }
    cout << "Answer sheet loaded" << endl;

    // Load classification file names
    ifstream readClassificationFileListFile;
    readClassificationFileListFile.open(readClassificationFileList);
    vector<string> readClassificationFileNames;
    if (readClassificationFileListFile.is_open()) {
        while (getline(readClassificationFileListFile, eachLine)) {
            readClassificationFileNames.push_back(eachLine);
        }
    } else {
        cerr << "Cannot open file for read classification file list" << endl;
    }
    cout << "Classification results loaded" << endl;

    size_t numberOfFiles = readClassificationFileNames.size();
    vector<GradeResult> results;
    results.resize(numberOfFiles);

#ifdef OPENMP
    omp_set_num_threads(par.threads);
#endif

#pragma omp parallel default(none), shared(results, ranks, numberOfFiles, mappingFileNames, readClassificationFileNames,\
par, cout, printColumnsIdx, cerr, names, nodes, merged)
    {
        // Grade each file
        unordered_map<string, int> assacc2taxid;
        vector<int> rightAnswers;
        vector<int> classList;
        vector<float> scoreList;   // empty unless --score-hist asked for it
        vector<string> readIds;
        vector<float> scores;
        string mappingFile;
        string readClassificationFileName;

        vector<string> ranks_local = ranks;

        TaxonomyWrapper ncbiTaxonomy(names, nodes, merged, false);
        cout << "Taxonomy loaded" << endl;

        // Print scores of TP and FP
        unordered_map<string, vector<size_t>> rank2TpIdx;
        unordered_map<string, vector<size_t>> rank2FpIdx;
        unordered_map<string, vector<size_t>> rank2FnIdx;
        vector<vector<string>> idx2values;
        // rank -> verdict (0 TP, 1 FP, 2 FN) -> bin. Allocated per file inside the parallel
        // region, merged under the critical section that already prints this file's result.
        unordered_map<string, array<vector<uint64_t>, 3>> scoreHistLocal;
        if (!par.scoreHist.empty()) {
            for (const auto & rank : ranks_local) {
                for (int v = 0; v < 3; ++v) {
                    scoreHistLocal[rank][v].assign(SCORE_BINS, 0);
                }
            }
        }
        if (!printColumnsIdx.empty()){
            for (const auto & rank : ranks_local) {
                rank2TpIdx[rank] = vector<size_t>();
                rank2FpIdx[rank] = vector<size_t>();
                rank2FnIdx[rank] = vector<size_t>();
            }
        }

#pragma omp for schedule(dynamic)
        for (size_t i = 0; i < numberOfFiles; ++i) {
            // Initialize
            assacc2taxid.clear();
            rightAnswers.clear();
            classList.clear();
            readIds.clear();
            scores.clear();
            if (!printColumnsIdx.empty()){
                for (const auto & rank : ranks_local) {
                    rank2TpIdx[rank].clear();
                    rank2FpIdx[rank].clear();
                    rank2FnIdx[rank].clear();
                }
            }
            mappingFile = mappingFileNames[i];
            readClassificationFileName = readClassificationFileNames[i];

            // Load the mapping file (answer sheet) (accession to taxID)
            string key, value;
            ifstream map;
            map.open(mappingFile);
            if (map.is_open()) {
                while (getline(map, key, '\t')) {
                    getline(map, value, '\n');
                    // remove version number
                    size_t pos = key.find('.');
                    if (pos != string::npos) {
                        key = key.substr(0, pos);
                    }
                    assacc2taxid[key] = stoi(value);
                }
                cout << "Answer file loaded" << endl;
            } else {
                cout << "Cannot open file for answer" << endl;
            }
            map.close();

            // Load classification results
            string resultLine;
            ifstream readClassification;
            readClassification.open(readClassificationFileName);
            vector<string> fields;
            string field;
            int classInt;

            vector<Score2> tpOrFp;
            regex regex1("(GC[AF]_[0-9]+\\.[0-9]+)");
            smatch assacc;
            size_t numberOfClassifications = 0;
            unordered_map<string, int> observed;
            while (getline(readClassification, resultLine, '\n')) {
                // skip line starting with '#'
                if (resultLine.empty() || resultLine[0] == '#') {
                    continue;
                }

                // Parse classification result
                fields = Util::split(resultLine, "\t");

                // A line with too few fields is fatal, not skipped. Every classifier this reads
                // writes one record per line with a fixed column count, so a short line means the
                // column indices do not match the file -- the whole run is being graded against
                // the wrong columns and the score would be silently meaningless. It also used to
                // be a segmentation fault: centrifuge's readID/seqID/taxID layout against the
                // metabuli defaults (--readid-col 1 --taxid-col 2) indexed past the end here.
                const size_t neededCols = static_cast<size_t>(
                    par.readIdCol > par.taxidCol ? par.readIdCol : par.taxidCol) + 1;
                // exit, not return: this loop sits inside the #pragma omp parallel above, and
                // branching out of a structured block is not allowed. The repository handles
                // fatal I/O the same way (relationStreamFatal).
                if (fields.size() < neededCols) {
                    cerr << "Error: " << readClassificationFileName << " has a line with "
                         << fields.size() << " tab-separated fields, but --readid-col "
                         << par.readIdCol << " --taxid-col " << par.taxidCol << " needs at least "
                         << neededCols << "." << endl;
                    cerr << "       The line was: " << resultLine << endl;
                    cerr << "       These are ZERO-based indices. Centrifuge writes"
                         << " readID/seqID/taxID, so it needs --readid-col 0 --taxid-col 2." << endl;
                    exit(EXIT_FAILURE);
                }

                // Skip the line if it is not a classification result
                if (fields[par.taxidCol].empty() || !isdigit(fields[par.taxidCol][0])) {
                    continue;
                }
                
                string id = fields[par.readIdCol];
                string fullId = id;
                if (par.testType == "gtdb") {
                    regex_search(id, assacc, regex1);
                    id = assacc[0];
                    // remove version number
                    size_t pos = id.find('.');
                    if (pos != string::npos) {
                        id = id.substr(0, pos);
                    }
                } else if (par.testType == "hiv" || par.testType == "hiv-ex") {
                    size_t pos = id.find('_');
                    id = id.substr(0, pos);
                } else if (par.testType == "cami" || par.testType == "cami-long" || par.testType == "cami-euk") {
                    size_t pos = id.find('/');
                    id = id.substr(0, pos);
                } else if (par.testType == "over") {
                    regex_search(id, assacc, regex1);
                    id = assacc[0];
                }

                classInt = stoi(fields[par.taxidCol]);

                // Skip if the read is already classified
                if (par.skipSecondary == 1) {
                    size_t pos = fullId.find('/');
                    fullId = fullId.substr(0, pos);
                    if (par.testType != "gtdb") {
                        cerr << "skipSecondary is only available for GTDB" << endl;
                        exit(1);
                    }
                    if (observed.find(fullId) == observed.end()) { // first observation
                        if (classInt != 0) { // classified
                            observed[fullId] = 1;
                        } else { // not classified
                            observed[fullId] = 0;
                            continue;
                        }
                    } else { // second observation
                        if (observed[fullId] == 1) { // already classified
                            continue;
                        } 
                    }
                }
                
                readIds.push_back(fullId);
                
                // Read ID -> right answer
                rightAnswers.push_back(assacc2taxid[id]);

                // Read classification
                
                classList.push_back(classInt);
                if (classInt != 0) {
                    numberOfClassifications++;
                }

                // The score this read was classified with. Three forms, because the three
                // classifiers do not write the same thing: a rate already on [0, 1]
                // (Metabuli), a raw score that has to be divided by a second column to
                // become one (Centrifuger's hit length over query length), and an LCA
                // mapping that has to be walked (Kraken2). Out-of-range columns are fatal
                // here for the same reason as above -- a silently absent score would draw a
                // histogram of zeros and the threshold read off it would be meaningless.
                if (!par.scoreHist.empty()) {
                    float sc = 0.0f;
                    if (par.kraken2Format) {
                        if (static_cast<size_t>(par.histScoreCol) >= fields.size()) {
                            cerr << "Error: --hist-score-col " << par.histScoreCol << " but "
                                 << readClassificationFileName << " has a line with only "
                                 << fields.size() << " fields (zero-based)." << endl;
                            exit(EXIT_FAILURE);
                        }
                        sc = kraken2Confidence(fields[par.histScoreCol], classInt, ncbiTaxonomy);
                    } else {
                        if (static_cast<size_t>(par.histScoreCol) >= fields.size()) {
                            cerr << "Error: --hist-score-col " << par.histScoreCol << " but "
                                 << readClassificationFileName << " has a line with only "
                                 << fields.size() << " fields (zero-based)." << endl;
                            exit(EXIT_FAILURE);
                        }
                        sc = strtof(fields[par.histScoreCol].c_str(), nullptr);
                        if (par.histDenomCol >= 0) {
                            if (static_cast<size_t>(par.histDenomCol) >= fields.size()) {
                                cerr << "Error: --hist-denom-col " << par.histDenomCol
                                     << " but " << readClassificationFileName
                                     << " has a line with only " << fields.size()
                                     << " fields (zero-based)." << endl;
                                exit(EXIT_FAILURE);
                            }
                            const float den = strtof(fields[par.histDenomCol].c_str(), nullptr);
                            sc = (den > 0.0f) ? sc / den : 0.0f;
                        }
                    }
                    scoreList.push_back(sc);
                }

                // Read column for printing. Bounds-checked for the same reason as the columns
                // above: --print-columns is given by hand and indexes `fields` directly.
                if (!printColumnsIdx.empty()) {
                    vector<string> values;
                    for (const auto &idx: printColumnsIdx) {
                        if (idx >= fields.size()) {
                            cerr << "Error: --print-columns names field " << idx << " but "
                                 << readClassificationFileName << " has a line with only "
                                 << fields.size() << " fields (zero-based)." << endl;
                            exit(EXIT_FAILURE);
                        }
                    }
                    for (const auto &idx: printColumnsIdx) {
                        values.push_back(fields[idx]);
                    }
                    idx2values.push_back(values);
                }
            }
            readClassification.close();

            // Score the classification
            char p;
            for (size_t j = 0; j < classList.size(); j++) {
                if (par.verbosity == 3) cout << readIds[j] << " " << classList[j] << " " << rightAnswers[j];
                for (const string &rank: ranks_local) {
                    if (par.testType == "over") {
                        p = compareTaxon_overclassification(classList[j], rightAnswers[j], ncbiTaxonomy,
                                                            results[i].countsAtRanks[rank], rank);
                    } else if(par.testType == "hiv-ex"){
                        p = compareTaxon_hivExclusion(classList[j], 11676, results[i].countsAtRanks[rank]);
                    } else if (par.testType == "cami-euk"){
                        p = compareTaxonAtRank_CAMI_euk(classList[j], rightAnswers[j], ncbiTaxonomy,
                                                        results[i].countsAtRanks[rank], rank);
                    } else {
                        p = compareTaxonAtRank_CAMI(classList[j], rightAnswers[j], ncbiTaxonomy,
                                                         results[i].countsAtRanks[rank], rank);
                    }
                    if (!printColumnsIdx.empty()) {
                        if (p == 'O') rank2TpIdx[rank].push_back(j);
                        else if (p == 'X') rank2FpIdx[rank].push_back(j);
                        else if (p == 'N') rank2FnIdx[rank].push_back(j);
                    }
                    // The verdict is read here and nowhere recomputed, so the histogram
                    // splits on exactly the TP/FP this command's precision and F1 are built
                    // from. Reads with no answer at this rank ('-') are left out, as they are
                    // left out of the score.
                    if (!par.scoreHist.empty() && j < scoreList.size()) {
                        int v = -1;
                        if (p == 'O') v = 0;
                        else if (p == 'X') v = 1;
                        else if (p == 'N') v = 2;
                        if (v >= 0) {
                            int b = (int)(scoreList[j] * SCORE_BINS);
                            if (b < 0) b = 0;
                            if (b >= SCORE_BINS) b = SCORE_BINS - 1;
                            scoreHistLocal[rank][v][b]++;
                        }
                    }
                    if (par.verbosity == 3) cout << " " << p;
                }
                if (par.verbosity == 3) cout << endl;
            }

            // Calculate the scores
            for (const string &rank: ranks_local) {
                results[i].countsAtRanks[rank].calculate();
            }

            // Write the values of TP, FP, and FN
            if (!printColumnsIdx.empty()) {
                for (const string & rank : ranks_local) {
                    // TP
                    ofstream tpFile;
                    tpFile.open(readClassificationFileName + "." + rank + ".tp");
                    for (const auto & idx : rank2TpIdx[rank]) {
                        for (const auto & value : idx2values[idx]) {
                            tpFile << value << "\t";
                        }
                        tpFile << endl;
                    }
                    tpFile.close();

                    // FP
                    ofstream fpFile;
                    fpFile.open(readClassificationFileName + "." + rank + ".fp");
                    for (const auto & idx : rank2FpIdx[rank]) {
                        for (const auto & value : idx2values[idx]) {
                            fpFile << value << "\t";
                        }
                        fpFile << endl;
                    }
                    fpFile.close();

                    // FN
                    ofstream fnFile;
                    fnFile.open(readClassificationFileName + "." + rank + ".fn");
                    for (const auto & idx : rank2FnIdx[rank]) {
                        for (const auto & value : idx2values[idx]) {
                            fnFile << value << "\t";
                        }
                        fnFile << endl;
                    }
                    fnFile.close();
                }
            }


            if (!par.scoreHist.empty()) {
                // `path` is otherwise never set -- nothing read it before this.
                results[i].path = readClassificationFileName;
                results[i].scoreHist = std::move(scoreHistLocal);
            }

            #pragma omp critical
            {   
                // Print Grade Result of each file
                cout << readClassificationFileName << endl;
                cout << "The number of reads: " << rightAnswers.size() << endl;
                cout << "The number of reads classified: " << numberOfClassifications << endl;
                for (const string &rank: ranks_local) {
                    const int noAnswer = results[i].countsAtRanks[rank].noAnswer;
                    if (noAnswer > 0) {
                        cout << "The number of reads without an answer at " << rank << ": "
                             << noAnswer << " (outside precision, sensitivity and F1)" << endl;
                    }
                }
                for (const string &rank: ranks_local) {
                    cout << rank << " " << results[i].countsAtRanks[rank].total << " "
                         << results[i].countsAtRanks[rank].TP + results[i].countsAtRanks[rank].FP << " "
                         << results[i].countsAtRanks[rank].TP << " " << results[i].countsAtRanks[rank].FP << " "
                         << results[i].countsAtRanks[rank].precision << " "
                         << results[i].countsAtRanks[rank].sensitivity << " " << results[i].countsAtRanks[rank].f1 << endl;
                }
                cout << endl;
            }
        }
    } // End of parallel region

    // One file for every input, since grade grades a list of them and a threshold is chosen
    // by looking at the arms together. Long format: a plotting script groups by the first
    // three columns and nothing has to be parsed out of a filename.
    if (!par.scoreHist.empty()) {
        ofstream hist(par.scoreHist);
        if (!hist.is_open()) {
            cerr << "Error: cannot open " << par.scoreHist << " for writing." << endl;
            return 1;
        }
        hist << "#file\trank\tverdict\tbin_lo\tbin_hi\tcount\n";
        const char * vname[3] = {"TP", "FP", "FN"};
        for (const auto & result : results) {
            for (const string & rank : ranks) {
                const auto it = result.scoreHist.find(rank);
                if (it == result.scoreHist.end()) { continue; }
                for (int v = 0; v < 3; ++v) {
                    const vector<uint64_t> & bins = it->second[v];
                    for (int b = 0; b < (int) bins.size(); ++b) {
                        // Empty bins are dropped. A 1000-bin table is mostly zeros on a score
                        // that piles up at one end, and the reader has the bin bounds.
                        if (bins[b] == 0) { continue; }
                        hist << result.path << "\t" << rank << "\t" << vname[v] << "\t"
                             << (double) b / SCORE_BINS << "\t"
                             << (double) (b + 1) / SCORE_BINS << "\t" << bins[b] << "\n";
                    }
                }
            }
        }
        hist.close();
        cout << "Score histogram written to " << par.scoreHist << endl;
    }

    cout << "Rank\t";
    for (size_t i = 0; i < results.size(); i++) {
        cout << "Precision\tSensitivity\tF1\t";
    }
    cout << endl;
    for (const string &rank: ranks) {
        cout << rank << "\t";
        for (auto & result : results) {
            cout << result.countsAtRanks[rank].precision << "\t" << result.countsAtRanks[rank].sensitivity
                 << "\t" << result.countsAtRanks[rank].f1 << "\t";
        }
        cout << endl;
    }
    return 0;
}

char compareTaxonAtRank_CAMI(TaxID shot, TaxID target, const TaxonomyWrapper & ncbiTaxonomy, CountAtRank & count,
                             const string & rank) {
    if (rank == "subspecies") {
        // Do not count if the rank of target is higher than current rank
        // current rank is subspecies
        // the rank of target is subspecies


        // False negative; no classification or meaningless classification
        if (shot == 1 || shot == 0) {
            count.FN ++;
            count.total ++;
            return 'N';
        }

        // False negative if the rank of shot is higher than current rank
        const TaxonNode * shotNode = ncbiTaxonomy.taxonNode(shot);
        if (strcmp(ncbiTaxonomy.getString(shotNode->rankIdx), "no rank") != 0) { // no rank is subspecies
            // cout << ncbiTaxonomy.getString(shotNode->rankIdx) << endl;
            count.FN ++;
            count.total ++;
            return 'N';
        }

        count.total++;
        if(shot == target){
            count.TP++;
            return 'O';
        } else {
            count.FP++;
            return 'X';
        }
    } else {
        // Do not count if the rank of target is higher than current rank
        TaxID targetTaxIdAtRank = ncbiTaxonomy.getTaxIdAtRank(target, rank);
        const TaxonNode * targetNode = ncbiTaxonomy.taxonNode(targetTaxIdAtRank);
        int rankIdx = ncbiTaxonomy.findRankIndex2(rank);
        // taxonNode returns null for taxon 0, which is what an absent answer looks like: the
        // caller reads the answer out of an unordered_map with operator[], so a read the answer
        // sheet does not carry becomes 0. getTaxIdAtRank also yields 0 when the answer has no
        // ancestor at this rank. Either way the read cannot be scored here.
        if (targetNode == nullptr) {
            count.noAnswer++;
            return '-';
        }
        if (ncbiTaxonomy.findRankIndex2(ncbiTaxonomy.getString(targetNode->rankIdx)) > rankIdx) {
            return '-';
        }
        
        // False negative; no classification or meaningless classification
        if(shot == 1 || shot == 0) {
            count.FN ++;
            count.total ++;
            return 'N';
        }

        // False negative if the rank of shot is higher than current rank
        TaxID shotTaxIdAtRank = ncbiTaxonomy.getTaxIdAtRank(shot, rank);
        const TaxonNode * shotNode = ncbiTaxonomy.taxonNode(shotTaxIdAtRank);
        // No ancestor at this rank means the classification sits above it, which is the miss
        // this branch already reports.
        if (shotNode == nullptr) {
            count.FN ++;
            count.total ++;
            return 'N';
        }
        if (ncbiTaxonomy.findRankIndex2(ncbiTaxonomy.getString(shotNode->rankIdx)) > rankIdx) {
            count.FN ++;
            count.total ++;
            return 'N';
        }   
        count.total++;
        if(shotTaxIdAtRank == targetTaxIdAtRank){
            count.TP++;
            return 'O';
        } else {
            count.FP++;
            return 'X';
        }
    }
}

char compareTaxonAtRank_CAMI_euk(TaxID shot, TaxID target, TaxonomyWrapper & ncbiTaxonomy, CountAtRank & count,
                             const string & rank) {
    // Do not count if the rank of target is higher than current rank
    TaxID targetTaxIdAtRank = ncbiTaxonomy.getTaxIdAtRank(target, rank);
    const TaxonNode * targetNode = ncbiTaxonomy.taxonNode(targetTaxIdAtRank);
    int rankIdx = NcbiTaxonomy::findRankIndex(rank);
    if (targetNode == nullptr) {
        count.noAnswer++;
        return '-';
    }
    if (NcbiTaxonomy::findRankIndex(ncbiTaxonomy.getString(targetNode->rankIdx)) > rankIdx) {
        return '-';
    }

    // Do not count if target is not eukaryote
    if (ncbiTaxonomy.getTaxIdAtRank(target, "superkingdom") != 2759) {
        return '-';
    }

    // False negative; no classification or meaningless classification
    if(shot == 1 || shot == 0) {
        count.FN ++;
        count.total ++;
        return 'N';
    }

    // False negative if the rank of shot is higher than current rank
    TaxID shotTaxIdAtRank = ncbiTaxonomy.getTaxIdAtRank(shot, rank);
    const TaxonNode * shotNode = ncbiTaxonomy.taxonNode(shotTaxIdAtRank);
    if (shotNode == nullptr) {
        count.FN ++;
        count.total ++;
        return 'N';
    }
    if (NcbiTaxonomy::findRankIndex(ncbiTaxonomy.getString(shotNode->rankIdx)) > rankIdx) {
        count.FN ++;
        count.total ++;
        return 'N';
    }

    count.total++;
    if(shotTaxIdAtRank == targetTaxIdAtRank){
        count.TP++;
        return 'O';
    } else {
        count.FP++;
        return 'X';
    }
}

char compareTaxon_overclassification(TaxID shot, TaxID target, TaxonomyWrapper & ncbiTaxonomy, CountAtRank & count,
                                     const string & rank){
    // Do not count if the rank of target is higher than current rank
//    TaxID targetTaxIdAtRank = ncbiTaxonomy.getTaxIdAtRank(target, rank);
    const TaxonNode * targetNode = ncbiTaxonomy.taxonNode(target);
    int rankIdx = NcbiTaxonomy::findRankIndex(rank);
    if (targetNode == nullptr) {
        count.noAnswer++;
        return '-';
    }
    if (NcbiTaxonomy::findRankIndex(ncbiTaxonomy.getString(targetNode->rankIdx)) > rankIdx) {
        return '-';
    }


    // False negative; no classification or meaningless classification
    if(shot == 1 || shot == 0) {
        count.FN ++;
        count.total ++;
        return 'N';
    }

    // False negative if the rank of shot is higher than current rank
    const TaxonNode * shotNode = ncbiTaxonomy.taxonNode(shot);
    if (shotNode == nullptr) {
        count.FN ++;
        count.total ++;
        return 'N';
    }
    if (NcbiTaxonomy::findRankIndex(ncbiTaxonomy.getString(shotNode->rankIdx)) > rankIdx) {
        count.FN ++;
        count.total ++;
        return 'N';
    }

    count.total++;
    if(shot == target){
        count.TP++;
        return 'O';
    } else {
        count.FP++;
        return 'X';
    }
}

// TP: HIV-1 at species rank
// FP: Classifications to other taxa
// FN: Not-classified
char compareTaxon_hivExclusion(TaxID shot, TaxID target, CountAtRank & count){
    // False negative; no classification or meaningless classification
    if(shot == 1 || shot == 0) {
        count.FN ++;
        count.total ++;
        return 'N';
    }
    count.total++;
    if(shot == target){
        count.TP++;
        return 'O';
    } else {
        count.FP++;
        return 'X';
    }
}

} // namespace grade_impl

int grade(int argc, const char **argv, const Command &command) {
    return grade_impl::grade(argc, argv, command);
}
