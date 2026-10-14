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

add_executable(metamoum
        ${commons_source_files}
        ${util_source_files}
        ${workflow_source_files}
        ${uniref_source_files}
        ${read_group_source_files}
        metamoum.cpp
        LocalCommandDeclarations.h
        MetamoumBase.cpp)

mmseqs_setup_derived_target(metamoum)
target_link_libraries(metamoum version)
target_link_libraries(metamoum prodigal)
target_link_libraries(metamoum fasta_validator)
target_link_libraries(metamoum fastq_utils)
target_link_libraries(metamoum yxml)
target_link_libraries(metamoum jsonlib)

install(TARGETS metamoum DESTINATION bin)
