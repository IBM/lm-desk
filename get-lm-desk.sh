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
uv_bin=$(find_cmd_bin uv || true)
obee_bin=$(find_cmd_bin obee || true)
beeai_bin=$(find_cmd_bin beeai || true)
jq_bin=$(find_cmd_bin jq || true)
install_path=""
default_model="granite3.3"
models="granite3.3 granite3.2-vision"
agents="gpt-researcher aider"
dry_run="0"
yes="1"
workdir=""

help_str="Usage: $0 [options]
Options:
    -h, --help               Show this help message
    -c, --curl-bin           Specify the path to curl (default is ${curl_bin})
    -b, --brew-bin           Specify the path to brew (default is ${brew_bin})
    -o, --ollama-bin         Specify the path to ollama (default is ${ollama_bin})
    -g, --git-bin            Specify the path to git (default is ${git_bin})
    -B, --beeai-bin          Specify the path to beeai (default is ${beeai_bin})
    -O, --obee-bin           Specify the path to obee (default is ${obee_bin})
    -j, --jq-bin             Specify the path to jq (default is ${jq_bin})
    -i, --install-path       Specify the install path for tools
    -d, --default-model      Specify the model to use by default (default is ${default_model})
    -m, --models             Specify the models to pull as a space-separated string (default is ${models})
    -a, --agents             Specify the agents to configure in obee as a space-separated string (default is ${agents})
    -k, --ask                Ask for confirmation
    -w, --workdir            Specify a work dir where temp files should live (default is ${workdir})
    -n, --dry-run            Run without installing anything"

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
        --beeai-bin|-B)
            beeai_bin="$2"
            shift
            ;;
        --obee-bin|-O)
            obee_bin="$2"
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
        --models|-m)
            models="$2"
            shift
            ;;
        --ask|-k)
            yes="0"
            ;;
        --workdir|-w)
            workdir="$2"
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

# If running without a TTY, always assume 'yes'
if ! [[ -t 1 ]]
then
    echo "RUNNING NON-INTERACTIVE"
    yes="1"
fi

## Helpers #####################################################################

#----
# Get a temporary working dir
#----
function work_dir {
    if [ "$workdir" == "" ]
    then
        workdir=$(mktemp -d)
    fi
    mkdir -p $workdir &>/dev/null
    echo $workdir
}


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
    brown "- obee: $obee_bin"
    brown "- git: $git_bin"
    brown "- beeai: $beeai_bin"
    brown "- obee: $obee_bin"
    brown "- jq: $jq_bin"
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
    echo "Installing Ollama using curl"
    if [ "$OS" == "Darwin" ]
    then
        echo "Installing on darwin"
        run "$curl_bin" -L -O https://ollama.com/download/Ollama-darwin.zip
        run unzip Ollama-darwin.zip
        run mv Ollama.app /Applications
        run rm Ollama-darwin.zip
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

    if [ "$OS" == "Darwin" ] || [ "$OS" == "Linux" ]
    then
        echo "Installing on linux"
        run curl -LsSf https://astral.sh/uv/install.sh | sh
        uv_bin="$(find_cmd_bin uv)"
    else
        fail "Cannot install uv using curl on $OS"
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
    # Otherwise, use curl to download ollama
    else
        install_ollama_curl
    fi
}


#----
# Start ollama if needed
#----
function start_ollama {
    ollama_pid=""
    if ! $ollama_bin ls &>/dev/null
    then
        green "Starting ollama"
        if [ "$dry_run" == "1" ]
        then
            run $ollama_bin serve > $(work_dir)/server.log 2>&1
        else
            $ollama_bin serve > $(work_dir)/server.log 2>&1 &
            ollama_pid=$!
        fi
    fi
    echo $ollama_pid
}

#----
# Stop ollama if given a valid PID
#----
function stop_ollama {
    ollama_pid=$1
    if [ "$ollama_pid" != "" ]
    then
        brown "Stopping ollama"
        kill $ollama_pid
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

    ollama_pid=$(start_ollama)
    for model in $models
    do
        run $ollama_bin pull $model
    done
    stop_ollama $ollama_pid
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

#----
# Install jq
#----
function install_jq {
    green "$(term_bar -)"
    bold green "INSTALLING JQ"
    green "$(term_bar -)"

    if [ "$curl_bin" != "" ]
    then
        green "Downloading temporary jq"
        plat=""
        if [ "$OS" == "Darwin" ]
        then
            plat="macos"
        elif [ "$OS" == "Linux" ]
        then
            plat="linux"
        else
            fail "Cannot install jq on $OS"
        fi
        suffix=""
        if [ "$ARCH" == "arm64" ]
        then
            suffix="arm64"
        elif [ "$ARCH" == "x86_64" ]
        then
            suffix="amd64"
        else
            bold red "Unable to install jq"
        fi
        if [ "$suffix" != "" ]
        then
            latest_jq_release=$(
                "$curl_bin" -s https://api.github.com/repos/jqlang/jq/releases/latest | \
                    grep '"tag_name":' | \
                    sed -E 's/.*"([^"]+)".*/\1/'
            )
            blue "Latest jq release: $latest_jq_release"
            run "$curl_bin" -L https://github.com/jqlang/jq/releases/download/${latest_jq_release}/jq-${plat}-${suffix} -o jq
            run chmod +x jq
            temp_bin=$(work_dir)
            jq_bin=$"$temp_bin/jq"
            mv jq $jq_bin
        fi
    else
        green "Installing jq with brew"
        run "$brew_bin" install jq
        jq_bin="$(find_cmd_bin jq)"
    fi
}


#----
# Install obee
#----
function install_obee {
    green "$(term_bar -)"
    bold green "INSTALLING OBEE"
    green "$(term_bar -)"

    # Only for MACOS at the moment
    if [ "$OS" == "Darwin" ]
    then
        # 1. Do the plist stuff
        $curl_bin -o $HOME/Library/LaunchAgents/com.granite.ollama.plist https://raw.githubusercontent.com/IBM/lm-desk/refs/heads/main/com.granite.ollama.plist
        $curl_bin -o $HOME/Library/LaunchAgents/com.granite.obee.plist https://raw.githubusercontent.com/IBM/lm-desk/refs/heads/main/com.granite.obee.plist

        open_webui_script=https://raw.githubusercontent.com/IBM/lm-desk/refs/heads/main/scripts/openwebui.py

        if [ "$ollama_bin" != "" ] && [ "$uv_bin" != "" ]; then
            sed -i '' -e 's|<OLLAMA_BIN>|'"$ollama_bin"'|g' $HOME/Library/LaunchAgents/com.granite.ollama.plist
            sed -i '' -e 's|<UV_BIN>|'"$uv_bin"'|g' $HOME/Library/LaunchAgents/com.granite.obee.plist
            sed -i '' -e 's|<OPEN_WEBUI_SCRIPT>|'"$open_webui_script"'|g' $HOME/Library/LaunchAgents/com.granite.obee.plist
        fi

        # 2. Do the brew tap stuff
        if [ "$brew_bin" != "" ]
        then
            run $brew_bin update
            run $brew_bin tap IBM/obee https://github.com/IBM/homebrew-obee
            run $brew_bin install obee
        # Otherwise, use curl to pull from GH release directly
        else
            echo "You are missing out"
        fi
    else
        fail "Cannot install obee on unsupported platform $OS"
    fi
    obee_bin=$(find_cmd_bin obee || true)
}


#----
# Configure beeai
#----
function configure_obee {
    green "$(term_bar -)"
    bold green "CONFIGURING OBEE"
    green "$(term_bar -)"

    # Make sure obee is running
    run obee start 2>/dev/null

    # Make sure beeai is running
    run $brew_bin services start beeai &>/dev/null

    # Ping both until they're up
    if [ "$dry_run" == "0" ]
    then
        for i in $(seq 1 120)
        do
            run $curl_bin http://localhost:8080/api/version &>/dev/null && \
            run $curl_bin http://localhost:8333/api/v1/openapi.json &>/dev/null && \
            break || \
            sleep 1
        done
    fi

    # Download the scripts for configuring the functions
    temp_dir=$(work_dir)
    run $curl_bin -o $temp_dir/beeai_function.py https://raw.githubusercontent.com/IBM/lm-desk/refs/heads/main/open-webui/beeai_function.py
    run $curl_bin -o $temp_dir/configure_openwebui.sh https://raw.githubusercontent.com/IBM/lm-desk/refs/heads/main/scripts/configure_openwebui.sh

    # Run the configured functions
    run chmod +x $temp_dir/configure_openwebui.sh
    if [ "$agents" != "" ]
    then
        agents_arg="{\"ENABLED_AGENTS\": ["
        for agent in $agents
        do
            agents_arg="$agents_arg\"$agent\""
            if [[ "$agents" != *$agent ]]
            then
                agents_arg="$agents_arg,"
            fi
        done
        agents_arg="$agents_arg]}"
        run $temp_dir/configure_openwebui.sh \
            -f $temp_dir/beeai_function.py \
            -d "Call agents from BeeAI" -v "$agents_arg"
    else
        run $temp_dir/configure_openwebui.sh \
            -f $temp_dir/beeai_function.py \
            -d "Call agents from BeeAI" $agents_arg
    fi
}


#----
# Install beeai
#----
function install_beeai {
    green "$(term_bar -)"
    bold green "INSTALLING BEEAI"
    green "$(term_bar -)"

    run $brew_bin install i-am-bee/beeai/beeai
    beeai_bin=$(find_cmd_bin beeai)
}

#----
# Configure beeai
#----
function configure_beeai {

    # Manually replicate the env setup process. This is done because there is no
    # way currently to script the answers to "env setup"

    # Figure out the right context size based on the user's machine
    context_size=32
    if [ "$OS" == "Darwin" ]
    then
        gb_mem=$(system_profiler -xml SPHardwareDataType \
            | grep -A 1 physical_memory \
            | grep "GB" | sed 's,[^0-9]*,,g')
        if [ "$gb_mem" -ge "64" ]
        then
            context_size=128
        elif [ "$gb_mem" == "32" ]
        then
            context_size=64
        fi
    fi
    if ! yes_no_prompt "Using context size ${context_size}k. Proceed?"
    then
        read -p "Enter a context length: " context_size 2>&1
    fi
    num_ctx=$(expr '1024' '*' $context_size)
    brown "Using context size ${context_size}k (num_ctx=${num_ctx})"

    # Create the local Ollama model
    ollama_pid=$(start_ollama)
    beeai_default_model="$default_model"
    if ! [[ "$beeai_default_model" == *":"* ]]
    then
        beeai_default_model="$beeai_default_model:latest"
    fi
    beeai_default_model="$beeai_default_model-beeai"
    brown "Default beeai model: $beeai_default_model"
    modelfile=$(work_dir)/Modelfile
    echo -e "FROM $default_model\nPARAMETER num_ctx $num_ctx" > $modelfile
    $ollama_bin create $beeai_default_model -f $modelfile

    # Configure beeai
    $beeai_bin env add LLM_API_BASE=http://localhost:11434/v1 &>/dev/null
    $beeai_bin env add LLM_API_KEY=ollama &>/dev/null
    $beeai_bin env add LLM_MODEL=$beeai_default_model &>/dev/null
    green "BEEAI CONFIG:"
    $beeai_bin env list
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
if [ "$brew_bin" == "" ] && { [ "$ollama_bin" == "" ] || [ "$beeai_bin" == "" ] || [ "$obee_bin" == "" ]; }
then
    need_brew="1"
fi
if [ "$need_brew" == "1" ]
then
    if yes_no_prompt "Install brew? **required**"
    then
        install_brew
        report_installed
    else
        exit
    fi
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

########################
# Install uv if needed #
########################
if [ "$uv_bin" == "" ] && yes_no_prompt "Install uv?"
then
    install_uv
    report_installed
fi

########################
# Install jq if needed #
########################
if [ "$jq_bin" == "" ] && yes_no_prompt "Install jq?"
then
    install_jq
    report_installed
fi

################
# Install obee #
################
if [ "$obee_bin" == "" ] &&  yes_no_prompt "Install obee?"
then
    install_obee
fi

#################
# Install beeai #
#################
if [ "$beeai_bin" == "" ] &&  yes_no_prompt "Install beeai?"
then
    install_beeai
fi

###################
# Configure beeai #
###################
if [ "$beeai_bin" != "" ] && yes_no_prompt "Configure beeai?"
then
    configure_beeai
fi

##################
# Configure obee #
##################
if [ "$obee_bin" != "" ] && [ "$beeai_bin" != "" ] && yes_no_prompt "Configure obee?"
then
    configure_obee
fi

####################################
# Open Web broswer (crossplatform) #
####################################
if yes_no_prompt "Open browser?"
then
    python_cmd=$(command -v python)
    if [ "$python_cmd" == "" ] || ! $python_cmd --version &>/dev/null
    then
        python_cmd=$(command -v python3)
    fi
    if [ "$python_cmd" == "" ] || ! $python_cmd --version &>/dev/null
    then
        uv_cmd=$(command -v uv)
        if [ "$uv_cmd" != "" ]
        then
            python_cmd="$uv_cmd run python"
        fi
    fi
    if [ "$python_cmd" == "" ] || ! $python_cmd --version &>/dev/null
    then
        red "NO PYTHON FOUND!"
        exit 1
    fi

    $python_cmd -m webbrowser http://localhost:8080
fi
