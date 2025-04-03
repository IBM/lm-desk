#!/usr/bin/env bash

################################################################################
# Welcome to LM Desk! This script will inspect your system and walk you through
# installing and configuring all of the LM Desk tools.
################################################################################

## CLI Args ####################################################################

#----
# Find a command's path
#
# @param cmd: The command to find
#----
function find_cmd_bin {
    command -v $1
}

OS=$(uname -s)
ARCH=$(uname -m)

curl_bin=$(find_cmd_bin curl || true)
brew_bin=$(find_cmd_bin brew || true)
ollama_bin=$(find_cmd_bin ollama || true)
git_bin=$(find_cmd_bin git || true)
code_bin=$(find_cmd_bin code || true)
uv_bin=$(find_cmd_bin uv || true)
jq_bin=$(find_cmd_bin jq || true)
install_path=""
chat_model="granite3.2:8b"
autocomplete_model="granite3.2:2b"
dry_run="0"
run_open_webui="0"

# If running without a TTY, always assume 'yes'
if [[ -t 1 ]]
then
    yes="0"
else
    echo "RUNNING NON-INTERACTIVE"
    yes="1"
fi


help_str="Usage: $0 [options]
Options:
    -h, --help               Show this help message
    -c, --curl-bin           Specify the path to curl (default is ${curl_bin})
    -b, --brew-bin           Specify the path to brew (default is ${brew_bin})
    -o, --ollama-bin         Specify the path to ollama (default is ${ollama_bin})
    -g, --git-bin            Specify the path to git (default is ${git_bin})
    -v, --vs-code-bin        Specify the path to code (default is ${code_bin})
    -j, --jq-bin             Specify the path to jq (default is ${jq_bin})
    -i, --install-path       Specify the install path for tools
    -p, --chat-model         Specify the path to chat model (default is ${chat_model})
    -a, --autocomplete-model Specify the path to autocomplete model (default is ${autocomplete_model})
    -y, --yes                Skip confirmation prompt
    -n, --dry-run            Run without installing anything
    -r, --run-owui           Run open web ui"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            echo -e "$help_str"
            exit 0
            ;;
        --curl-bin|-c)
            curl_bin="$2"
            shift
            ;;
        --brew-bin|-b)
            brew_bin="$2"
            shift
            ;;
        --ollama-bin|-o)
            ollama_bin="$2"
            shift
            ;;
        --git-bin|-g)
            git_bin="$2"
            shift
            ;;
        --vs-code-bin|-v)
            code_bin="$2"
            shift
            ;;
        --jq-bin|-j)
            jq_bin="$2"
            shift
            ;;
        --install-path|-i)
            install_path="$2"
            shift
            ;;
        --chat-model|-p)
            chat_model="$2"
            shift
            ;;
        --autocomplete-model|-a)
            autocomplete_model="$2"
            shift
            ;;
        --yes|-y)
            yes="1"
            ;;
        --dry-run|-n)
            dry_run="1"
            ;;
        --run-owui|-r)
            run_open_webui="1"
            ;;
        *)
            echo "Invalid argument: $1" >&2
            echo -e "$help_str"
            exit 1
            ;;
    esac
    shift
done

# Set up the default vs code CLI path
if  [ "$code_bin" == "" ] && \
    [ -f "/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code" ] && \
    [ -x "/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code" ]
then
    code_bin="/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code"
fi

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
    if [[ -t 1 ]] && type tput &> /dev/null
    then
        tput bold
    fi
    $@
}

#----
# Color echo aliases
#
# @param ...: Passthrough text
#----
function red { echo_color 1 "$@"; }
function green { echo_color 2 "$@"; }
function brown { echo_color 3 "$@"; }
function blue { echo_color 4 "$@"; }
function magenta { echo_color 5 "$@"; }

#----
# Repeate the given character a given number of times
# NOTE: This doesn't work in zsh
#
# @param str: The string to repeat
# @param n: The number of times to repeat it
#----
function repeat {
    local str=$1 n=$2 spaces
    printf -v spaces "%*s" $n " "
    printf "%s" "${spaces// /$str}"
}

#----
# Create a term-width printed bar with the given character
#
# @param char: The character to repeat
#----
function term_bar {
    char=$1
    if [[ -t 1 ]] && type tput &> /dev/null
    then
        term_width=$(tput cols)
    else
        term_width=5
    fi
    repeat $char $term_width
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
# Fail and exit
#----
function fail {
    bold red "FATAL: $@"
    exit 1
}

#----
# Check if a dir is writable
#
# @param dirname
#----
function writable {
    touch $1/tmp &>/dev/null && rm $1/tmp
}

#----
# Prompt the user to answer a yes/no question
# NOTE: This doesn't work with zsh
#
# @param user_prompt: Prompt text
#----
function yes_no_prompt {
    if [ "$yes" == "1" ]
    then
        return 0
    fi
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
# Make sure that there's a valid install_path set
#----
function ensure_install_path {

    if [ "$install_path" != "" ]
    then
        return 0
    fi

    # Preference order of paths to use
    path_prefs=(
        $HOME/.local/bin
        $HOME/bin
        /usr/local/bin
        /usr/bin
        /bin
    )

    # Look for a place on PATH to put ollama
    IFS=:
    path_elements=(${PATH})
    unset IFS
    for path_pref in "${path_prefs[@]}"
    do
        if writable $path_pref
        then
            for element in ${path_elements[@]}
            do
                if [ "$path_pref" == "$element" ]
                then
                    install_path=$element
                    brown "Install Path: $install_path"
                    return 0
                fi
            done
        fi
    done

    # If none of the preferred paths is found, iterate the other paths
    for element in ${path_elements[@]}
    do
        if writable $element
        then
            if yes_no_prompt "Use install path <$element>?"
            then
                install_path=$element
                brown "Install Path: $install_path"
                return 0
            fi
        fi
    done

    # If no install path found, use ~/.local/bin and warn
    install_path="$HOME/.local/bin"
    brown "Install Path: $instll_path"
    mkdir -p $install_path
    red "Unable to find a writable install path. Using $install_path."
    red "IMPORTANT! You won't be able to use the tools until you add $install to PATH"
}

#----
# Report all of the currently installed binaries
#----
function report_installed {
    brown $(term_bar -)
    bold brown "INSTALLED COMMANDS:"
    brown "- curl: $curl_bin"
    brown "- brew: $brew_bin"
    brown "- ollama: $ollama_bin"
    brown "- uv: $uv_bin"
    brown "- git: $git_bin"
    brown "- code: $code_bin"
    brown $(term_bar -)
}

## Installers ##################################################################

#----
# Install curl on various platforms
#----
function install_curl {
    green "$(term_bar -)"
    bold green "INSTALLING CURL"
    green "$(term_bar -)"
    if type apt-get &>/dev/null
    then
        run apt-get update
        run apt-get install -y curl
    elif type yum &>/dev/null
    then
        run yum update
        run yum install -y curl
    elif type microdnf &>/dev/null
    then
        run microdnf update
        run microdnf install -y curl
    fi
    curl_bin=$(find_cmd_bin curl)
}


#----
# Install homebrew
#----
function install_brew {
    green "$(term_bar -)"
    bold green "INSTALLING HOMEBREW"
    green "$(term_bar -)"
    if [ "$OS" == "Darwin" ] || [ "$OS" == "Linux" ]
    then
        run bash -c "$($curl_bin -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew_bin=$(find_cmd_bin brew)
    else
        fail "Cannot install brew on unsupported platform $OS"
    fi
}


#----
# Install ollama with homebrew
#----
function install_ollama_brew {
    echo "Using brew ($brew_bin)"
    run $brew_bin install ollama
    ollama_bin=$(find_cmd_bin ollama)
}

#----
# Install uv with homebrew
#----
function install_uv_brew {
    echo "Using brew ($brew_bin)"
    run $brew_bin install uv
    uv_bin=$(find_cmd_bin uv)
}


#----
# Install ollama with curl from github
#----
function install_ollama_curl {
    echo "Installing ollama from GitHub Release"
    latest_release=$(
        "$curl_bin" -s https://api.github.com/repos/ollama/ollama/releases/latest | \
            grep '"tag_name":' | \
            sed -E 's/.*"(v?[^"]+)".*/\1/'
    )
    blue "Latest release: $latest_release"
    if [ "$OS" == "Darwin" ]
    then
        echo "Installing on darwin"
        run "$curl_bin" -L https://github.com/ollama/ollama/releases/download/${latest_release}/ollama-darwin -o ollama
        run chmod +x ollama
        ensure_install_path
        ollama_bin="$install_path/ollama"
        run mv ollama $ollama_bin
    elif [ "$OS" == "Linux" ]
    then
        echo "Installing on linux"
        run curl -fsSL https://ollama.com/install.sh | sh
        ollama_bin="$(find_cmd_bin ollama)"
    else
        fail "Cannot install ollama using curl with OS[$OS]/ARCH[$ARCH]"
    fi
}

#----
# Install uv with curl 
#----
function install_uv_curl {
    echo "Installing uv with curl"
    
    if [ "$OS" == "Darwin" ]
    then
        echo "Installing on darwin -- not ready yet"
    elif [ "$OS" == "Linux" ]
    then
        echo "Installing on linux"
        run curl -LsSf https://astral.sh/uv/install.sh | sh
        uv_bin="$(find_cmd_bin uv)"
    else
        fail "Cannot install uv using curl with OS[$OS]/ARCH[$ARCH]"
    fi
}

#----
# Top-level ollama installer
#----
function install_ollama {
    green "$(term_bar -)"
    bold green "INSTALLING OLLAMA"
    green "$(term_bar -)"

    # If brew is available use brew
    if [ "$brew_bin" != "" ]
    then
        install_ollama_brew
    # Otherwise, use curl to pull from GH release directly
    else
        install_ollama_curl
    fi
}


#----
# Pull ollama models
#----
function pull_models {
    green "$(term_bar -)"
    bold green "PULLING MODELS"
    green "(This may take a long time based on your internet speed)"
    green "$(term_bar -)"
    if [ "$ollama_bin" == "" ]
    then
        fail "Cannot pull models without ollama"
    fi

    # Run the ollama server if needed
    ollama_pid=""
    if ! $ollama_bin ls &>/dev/null
    then
        green "Starting ollama"
        if [ "$dry_run" == "1" ]
        then
            run $ollama_bin serve
        else
            $ollama_bin serve &
            ollama_pid=$!
        fi
    fi

    run $ollama_bin pull $chat_model
    run $ollama_bin pull $autocomplete_model

    # Shut down ollama if neded
    if [ "$ollama_pid" != "" ]
    then
        brown "Stopping ollama"
        kill $ollama_pid
    fi
}


#----
# Install uv 
#----
function install_uv {
    green "$(term_bar -)"
    bold green "INSTALLING UV"
    green "$(term_bar -)"

    # If brew is available use brew
    if [ "$brew_bin" != "" ]
    then
        install_uv_brew
    # Otherwise, use curl to pull from GH release directly
    else
        install_uv_curl
    fi
}


## Main ########################################################################
report_installed

#######################################
# Install curl to install other tools #
#######################################
if [ "$curl_bin" == "" ]
then
    yes_no_prompt "Install curl?"
    install_curl
    report_installed
fi

#################################################
# Install brew if needed to install other tools #
#################################################
need_brew="0"
if [ "$ollama_bin" == "" ]
then
    if [ "$brew_bin" == "" ] && [ "$curl_bin" == "" ]
    then
        need_brew="1"
    fi
fi
if [ "$need_brew" == "1" ] && yes_no_prompt "Install brew?"
then
    install_brew
    report_installed
fi


############################
# Install ollama if needed #
############################
if [ "$ollama_bin" == "" ] && yes_no_prompt "Install ollama?"
then
    install_ollama
    report_installed
fi


###############
# Pull models #
###############
if [ "$ollama_bin" != "" ] && yes_no_prompt "Pull models?"
then
    pull_models
fi

############################
# Install uv if needed #
############################
if [ "$uv_bin" == "" ] && yes_no_prompt "Install uv?"
then
    install_uv
    report_installed
fi


############################
# Run everything 
############################
if [ "$run_open_webui" == "0" ] && yes_no_prompt "Run Openwebui?"
then
    run $ollama_bin start |
    run $uv_bin run https://raw.githubusercontent.com/vedem1192/lm-desk/refs/heads/main/scripts/openwebui.py
fi