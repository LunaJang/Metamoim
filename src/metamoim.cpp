#include "Command.h"
#include "LocalParameters.h"

const char* binary_name = "metamoim";
const char* tool_name = "metamoim";
const char* tool_introduction = "Metamoim groups metagenomic reads by the k-mers they share, and propagates a group's label to its unlabelled members.";
const char* main_author = "Luna Sung-eun Jang <jse9512@gmail.com>";
const char* show_extended_help = "1";
const char* show_bash_info = nullptr;
bool hide_base_commands = true;
extern const char* MMSEQS_CURRENT_INDEX_VERSION;
const char* index_version_compatible = MMSEQS_CURRENT_INDEX_VERSION;
bool hide_base_downloads = true;
void (*validatorUpdate)(void) = 0;

extern std::vector<Command> baseCommands;
extern std::vector<Command> metamoimCommands;
extern std::vector<Categories> categories;
void init() {
        for (size_t i = 0; i < categories.size(); ++i) {
            if (categories[i].mode & COMMAND_MAIN) {
                categories[i].title = "Read grouping workflows";
            }
            if (categories[i].mode & COMMAND_DATABASE_CREATION) {
                categories[i].title = "Database workflows";
            }
            if (categories[i].mode & COMMAND_FORMAT_CONVERSION) {
                categories[i].title = "Downstream workflows";
            }
        }
    registerCommands(&metamoimCommands);
}
void (*initCommands)(void) = init;

void initParameterSingleton() { new LocalParameters; }
