#!/usr/bin/env bash

################################################################################
# WARNING! This script can be destructive to your system and should not be run
# in an environment that cannot be safely destroyed!
################################################################################

## CLI Args ####################################################################

backup_dir="backup"
purge_brew=0
purge_ollama=0
purge_vs_code=0
purge_continue=0
purge_jq=0
purge_ollama_bar=0
purge_models=""
dry_run=0

help_str="Usage: $0 [options]
Options:
    -h, --help       Print this help message and exit
    -d, --backup     Directory where backups should be put
    -b, --brew       Purge brew
    -o, --ollama     Purge ollama
    -v, --vs-code    Purge vs code
    -c, --continue   Purge continue
    -j, --jq         Purge jq
    -l, --ollama-bar Purge ollama-bar
    -m, --model      Purge the given model (may be set multiple times)
    -n, --dry-run    Do a dry run, don't actually delete anything
"
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            echo -e "$help_str"
            exit 0
            ;;
        --backup|-d)
            backup_dir="$2"
            shift
            ;;
        --brew|-b)
            purge_brew="1"
            ;;
        --ollama|-o)
            purge_ollama="1"
            ;;
        --vs-code|-v)
            purge_vs_code="1"
            ;;
        --continue|-c)
            purge_continue="1"
            ;;
        --jq|-j)
            purge_jq="1"
            ;;
        --models|-m)
            if [ "$purge_models" != "" ]
            then
                purge_models="$purge_models "
            fi
            purge_models="$purge_models$2"
            shift
            ;;
        --dry-run|-n)
            dry_run="1"
            ;;
        *)
            echo "Invalid argument: $1" >&2
            echo -e "$help_str"
            exit 1
            ;;
    esac
    shift
done

ollama_bin="${OLLAMA_BIN:-$(command -v ollama || true)}"
code_bin="${CODE_BIN:-$(command -v code || true)}"
brew_bin="${BREW_BIN:-$(command -v brew || true)}"


## Helpers #####################################################################

#----
# Echo the given text with the given color code highlight
#
# @param color_code: The tput color number
# @param ...: Passthrough text to colorize
#----
function echo_color {
    color=''
    bold=''
    reset=''
    color_code=$1
    shift
    if [[ -t 1 ]] && type tput &> /dev/null
    then
        color=$(tput setaf $color_code)
        reset=$(tput sgr0)
    fi
    echo "${color}$@${reset}"
}

#----
# Apply bold to the passthrough text
#
# @param ...: Passthrough text
#----
function bold {
    tput bold
    $@
}

#----
# Color echo aliases
#
# @param ...: Passthrough text
#----
function red { echo_color 1 $@; }
function green { echo_color 2 $@; }
function brown { echo_color 3 $@; }
function blue { echo_color 4 $@; }
function magenta { echo_color 5 $@; }

#----
# Prompt the user to answer a yes/no question
# NOTE: This doesn't work with zsh
#
# @param user_prompt: Prompt text
#----
function yes_no_prompt {
    user_prompt=$1
    read -p "$user_prompt [Y/n]: " resp 2>&1
    if [ "$resp" == "" ] || [ "$resp" == "y" ] || [ "$resp" == "Y" ]
    then
        return 0
    elif [ "$resp" == "n" ] || [ "$resp" == "N" ]
    then
        return 1
    else
        echo "Bad response [$resp]"
        yes_no_prompt $user_prompt
    fi
}

#----
# Echo the command in dry run, otherwise execute it
#
# param: ...: Passthrough command and args
#----
function run {
    if [ "$dry_run" == "1" ]
    then
        magenta "DRY RUN [$@]"
    else
        "$@"
    fi
}

#----
# Simple absolute path function (more portable than realpath)
#
# @param fname: The path to make absolute
#----
function abs_path {
    fname=$1
    echo $(cd $(dirname $fname) && pwd)/$(basename $fname)
}

#----
# Back up the given file or directory into the backup dir
#
# @param fname: The file or directory name to back up
#----
function backup {
    fname=$1
    abs=$(abs_path $fname)
    backup_path=$backup_dir/$abs
    mkdir -p $(dirname $backup_path) 2>/dev/null
    cp -r $fname $backup_path
}

#----
# Check whether a given package was installed by brew
#
# @param package: The name of the brew package
#----
function installed_by_brew {
    [ "$brew_bin" != "" ] && [ "$($brew_bin info $1 2>/dev/null | grep "Installed" 2>/dev/null)" == "Installed" ]
}

## Main ########################################################################

bold red "WARNING: This script can be destructive to your system! Proceed with caution"
yes_no_prompt "Do you want to continue?" && bold green "Proceeding..." || bold red "Aborting..."

# Make sure the backup dir exists
backup_dir="$(abs_path $backup_dir)"
mkdir -p $backup_dir
blue "Backup Dir: $backup_dir"


################
# Purge Models #
################

if [ "$purge_models" == "1" ]
then
    # Run ollama if needed
    ollama_pid=""
    if ! $ollama_bin ls &>/dev/null
    then
        green "Starting ollama"
        run $ollama_bin serve &
        ollama_pid=$(ps aux | grep "$ollama_bin serve" | grep -v grep | sed 's,  *, ,g' | cut -d' ' -f2)
    fi

    # Purge all the models
    purge_models=($purge_models)
    for model in "${purge_models[@]}"
    do
        green "Purging $model"
        run $ollama_bin rm $model
    done

    # Shut down ollama if needed
    if [ "$ollama_pid" != "" ]
    then
        brown "Stopping ollama"
        kill $ollama_pid
    fi
fi

################
# Purge ollama #
################

if [ "$purge_ollama" == "1" ]
then
    green "Purging ollama"
    run backup $HOME/.ollama
    if installed_by_brew ollama
    then
        green "Uninstalling with brew"
        run brew uninstall ollama
    else
        green "Removing manual install"
        run backup $ollama_bin
        run rm -rf $(abs_path $ollama_bin)
    fi
    run rm -rf $HOME/.ollama
fi

##################
# Purge continue #
##################

if [ "$purge_continue" == "1" ]
then
    green "Purging continue"
    run backup $HOME/.continue
    run $code_bin --uninstall-extension "continue.continue"
    run rm -rf $HOME/.continue
fi

## TODO -- Not supported yet
if [ "$purge_brew" == "1" ]
then
    red "UNIMPLEMENTED --brew"
fi
if [ "$purge_vs_code" == "1" ]
then
    red "UNIMPLEMENTED --vs-code"
fi
if [ "$purge_jq" == "1" ]
then
    red "UNIMPLEMENTED --jq"
fi
if [ "$purge_ollama_bar" == "1" ]
then
    red "UNIMPLEMENTED --ollama-bar"
fi