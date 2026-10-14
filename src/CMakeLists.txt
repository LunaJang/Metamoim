include_directories(commons)
include_directories(workflow)
include_directories(util)
include_directories(uniref)
include_directories(read-group)
include_directories(../lib/prodigal)
include_directories(../lib/fasta_validator)
include_directories(../lib/fastq_utils)
include_directories(../lib/yxml)
include_directories(../lib/json)

add_subdirectory(commons)
add_subdirectory(util)
add_subdirectory(version)
add_subdirectory(workflow)
add_subdirectory(uniref)
add_subdirectory(read-group)

add_executable(metamoim
        ${commons_source_files}
        ${util_source_files}
        ${workflow_source_files}
        ${uniref_source_files}
        ${read_group_source_files}
        metamoim.cpp
        LocalCommandDeclarations.h
        MetamoimBase.cpp)

mmseqs_setup_derived_target(metamoim)
target_link_libraries(metamoim version)
target_link_libraries(metamoim prodigal)
target_link_libraries(metamoim fasta_validator)
target_link_libraries(metamoim fastq_utils)
target_link_libraries(metamoim yxml)
target_link_libraries(metamoim jsonlib)

install(TARGETS metamoim DESTINATION bin)
