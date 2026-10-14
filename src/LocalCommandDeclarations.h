#ifndef METAMOUM_LOCALCOMMANDDECLARATIONS_H
#define METAMOUM_LOCALCOMMANDDECLARATIONS_H
#include "Command.h"

extern int groupGeneration(int argc, const char **argv, const Command& command);
extern int easyGroupGeneration(int argc, const char **argv, const Command& command);
extern int groupApplication(int argc, const char **argv, const Command& command);
extern int create_common_kmer_list(int argc, const char **argv, const Command& command);
extern int count_common_kmers(int argc, const char **argv, const Command& command);
extern int gradeGroup(int argc, const char **argv, const Command& command);
extern int gradeGroupByCoverage(int argc, const char **argv, const Command& command);
extern int gradeStrain(int argc, const char **argv, const Command& command);

#endif //METAMOUM_LOCALCOMMANDDECLARATIONS_H
