#include "LocalUtil.h"
#include <cctype>
#include <fstream>

bool LocalUtil::loadAnswerMapping(const std::string & mappingFile,
                                  const std::string & testType,
                                  std::unordered_map<std::string, int> & assacc2taxid) {
    std::ifstream map(mappingFile);
    if (!map.is_open()) {
        return false;
    }

    const bool cami = (testType == "cami" || testType == "cami-long" || testType == "cami-euk");
    std::string line;
    while (std::getline(map, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line.empty() || line[0] == '#') {
            continue;
        }

        const size_t firstTab = line.find('\t');
        if (firstTab == std::string::npos) {
            continue;
        }
        std::string key = line.substr(0, firstTab);
        std::string value;

        if (cami) {
            const size_t slash = key.rfind('/');
            if (slash != std::string::npos) {
                key = key.substr(0, slash);
            }
            const size_t secondTab = line.find('\t', firstTab + 1);
            if (secondTab == std::string::npos) {
                value = line.substr(firstTab + 1);
            } else {
                const size_t thirdTab = line.find('\t', secondTab + 1);
                value = (thirdTab == std::string::npos)
                        ? line.substr(secondTab + 1)
                        : line.substr(secondTab + 1, thirdTab - secondTab - 1);
            }
        } else {
            const size_t dot = key.find('.');
            if (dot != std::string::npos) {
                key = key.substr(0, dot);
            }
            value = line.substr(firstTab + 1);
        }

        if (value.empty() || !isdigit(static_cast<unsigned char>(value[0]))) {
            continue;
        }
        assacc2taxid[key] = std::stoi(value);
    }
    return true;
}


std::string LocalUtil::getQueryBaseName(const std::string & queryPath) {
    std::vector<std::string> splits = Util::split(queryPath, ".");
    std::string baseName;
    int extentionNum = 1;
    if (Util::endsWith(".gz", queryPath)) {
        extentionNum = 2;
    }
    for (size_t i = 0; i < splits.size() - extentionNum; ++i) {
        if (i == splits.size() - extentionNum - 1) {
            baseName += splits[i];
        } else {
            baseName += splits[i] + ".";
        }
    }
    return baseName;
}

int LocalUtil::getFirstWhiteSpacePos(const std::string &str) {
    for (size_t i = 0; i < str.size(); ++i) {
        if (isspace(int(str[i]))) {
            return i;
        }
    }
    return str.size();
}

// std::string LocalUtil::getAccessionFromHeader(const std::string &header) {
//     int pos = getFirstWhiteSpacePos(header);
//     std::string accession = header.substr(0, pos);
//     std::vector<std::string> splits = Util::split(accession, ".");
//     if (splits.size() > 1) {
//         accession = splits[0];
//     }
//     return std::stoi(accession.substr(3));
// }