#!/usr/bin/env bash

# Fields to parse from the ollama timing output
time_fields=(
    "total duration"
    "load duration"
    "prompt eval count"
    "prompt eval duration"
    "prompt eval rate"
    "eval count"
    "eval duration"
    "eval rate"
)

models=()
default_models=(
    granite-code:3b
    granite-code:8b
    granite-code:20b
    granite-code:34b
)
output_file="output.csv"
pull="0"
verbose="0"
prompt="Write a python class that represents User. A user will need a name, email address, bio, and a list of roles they have access to."

help_str="Usage: $0 [options]
Options:
  --help, -h    Print this help message and exit.
  --model, -m   Specify a model to measure. May be specified multiple times.
  --output, -o  Specify the file to write results to.
  --prompt, -p  The prompt to use for the measurements.
  --pull, -l    Pull models before testing them.
  --verbose, -v Print verbose output.
"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            echo -e "$help_str"
            exit 0
            ;;
        --model|-m)
            models+=($2)
            shift
            ;;
        --output|-o)
            output_file="$2"
            shift
            ;;
        --prompt|-p)
            prompt="$2"
            shift
            ;;
        --pull|-l)
            pull="1"
            ;;
        --verbose|-v)
            verbose="1"
            ;;
        *)
            echo "Invalid argument: $1" >&2
            echo -e "$help_str"
            exit 1
            ;;
    esac
    shift
done

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
    echo -e "${color}$@${reset}"
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
# Escape a string to go into the output CSV
#
# @param ...: The string to escape
#----
function csv_escape {
    echo "${@//
/\n}" | sed 's/,/\\,/g'
}

#----
# Remove ansii escape sequences from a string
#
# @param ...: The string to strip
#----
function strip_ansi {
    echo "$@" | sed -r 's/\x1B\[[0-9;]*m//g'
}


#----
# Measure the time to load a model and run a prompt
#
# @param model: The model to measure
# @param prompt: The prompt to use
#----
function measure_model {
    model=$1
    prompt=$2

    # Make sure the model is NOT currently loaded by running it with a 0s
    # keepalive
    if ollama ps | grep $model &>/dev/null
    then
        brown "Unloading $model"
        ollama run $model "this is a test" --keepalive "0s" &>/dev/null
    fi

    # Run the inference with verbose mode to show timing
    # NOTE: We use a temp file here since ollama hasn't merged --quiet to
    #   suppress the control characters that go to stderr
    #    https://github.com/ollama/ollama/pull/6130
    output=$(ollama run $model $prompt --keepalive "0s" --verbose 2>timing.tmp)
    timing_out=$(cat timing.tmp)
    rm timing.tmp
    echo "$timing_out"

    if [ "$verbose" == "1" ]
    then
        green "$output"
    fi

    # Add a line to the output
    model_line="\"$model\", \"$(csv_escape "$prompt")\", \"$(csv_escape "$output")\""
    for field in "${time_fields[@]}"
    do
        time_val=$(echo -e "$timing_out" | grep --color=never "^$field" | cut -d':' -f 2 | sed 's,^ *,,g')
        model_line="$model_line, \"$time_val\""
    done
    echo "$model_line" >> $output_file
}

## Main ########################################################################

if [ "${#models}" == "0" ]
then
    models=(${default_models[@]})
    brown "Using default models: ${models[@]}"
fi


# Add the header to the output file
header_line="MODEL, PROMPT, OUTPUT"
for field in "${time_fields[@]}"
do
    header_line="${header_line}, \"$field\""
done
echo $header_line > $output_file

# Print out the prompt
bold magenta "PROMPT:"
magenta "$prompt"
echo "----"

# Iterate the models and evaluate each one
for model in "${models[@]}"
do
    blue "Testing model $model"
    if [ "$pull" == "1" ]
    then
        brown "Pulling $model"
        ollama pull $model
    fi
    measure_model $model "$prompt"
done