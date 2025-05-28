#!/usr/bin/env bash

################################################################################
# This is a helper script to upload a function through Open WebUI.
################################################################################

# Function to parse CLI arguments
parse_args() {
    # Initialize default values
    open_webui_url="http://localhost:8080"
    function_file=""
    function_name=""
    description=""
    valves=""
    verbose=0

    # Process each argument
    while [[ $# > 0 ]]; do
        case "$1" in
            -u|--open-webui-url)
                open_webui_url="$2"
                shift
                ;;
            -f|--function-file)
                function_file="$2"
                shift
                ;;
            -n|--function-name)
                function_name="$2"
                shift
                ;;
            -d|--description)
                description="$2"
                shift
                ;;
            -v|--valves)
                valves="$2"
                shift
                ;;
            -V|--verbose)
                verbose=1
                ;;
            *) # Unknown option, handle error
                echo "Error: Unknown option '$1'"
                echo "Usage: $0 [--open-webui-url URL] --function-file FILE_PATH [-d DESCRIPTION]"
                exit 1
                ;;
        esac
        shift
    done

    if [ -z "$function_file" ]; then
        echo "Error: --function-file is required."
        exit 1
    fi
    if [ "$function_name" == "" ]; then
        function_name=$(basename $function_file | rev | cut -d'.' -f 2- | rev | sed 's,[_-], ,g')
    fi
    function_id=$(echo "$function_name" | sed 's, ,_,g')
    api_base_url=$(echo "$open_webui_url" | sed 's,/$,,g')/api/v1
}

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
function red { echo_color 1 "$@"; }
function green { echo_color 2 "$@"; }
function brown { echo_color 3 "$@"; }
function blue { echo_color 4 "$@"; }
function magenta { echo_color 5 "$@"; }

# Call the function to parse arguments
parse_args "$@"
brown "Open Webui URL: $open_webui_url"
brown "Open Webui API URL: $api_base_url"
brown "Function File Path: $function_file"
brown "Function Name: $function_name"
brown "Function ID: $function_id"
brown "Description: $description"
brown "Verbose: $verbose"

# Sign in and get a token
# NOTE: This assumes running without auth!
token=$(curl -s $api_base_url/auths/signin \
    -X POST \
    -H "Content-Type: application/json" \
    -d'{"email": "", "password": ""}' | jq -r .token)

function api_call {
    endpoint=$1
    shift
    method=$1
    shift
    curl -s ${api_base_url}/$endpoint \
        -X $method \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" "$@"
}

function step_api_call {
    step=$1
    shift
    blue $step...
    res=$(api_call "$@")
    if [ "$?" == "0" ]
    then
        green OK
    else
        red FAIL
        return 1
    fi
    if [ "$verbose" == "1" ]
    then
        echo $res | jq
    fi
}

function function_exists {
    api_call functions/id/$1 GET -v 2>&1 | grep "HTTP/[^ ]* 200 OK" &>/dev/null
}

function function_active {
    api_call functions/id/$1 GET | jq -r ".is_active"
}

# Check to see if the function already exists
if function_exists $function_id; then
    echo "Function [$function_id] already exists!"
    post_endpoint="functions/id/$function_id/update"
else
    echo "Function [$function_id] doesn't exist!"
    post_endpoint="functions/create"
fi

# Create the function
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
body=$($python_cmd -c "import json; print(json.dumps({
    \"id\":\"$function_id\",
    \"name\": \"$function_name\",
    \"content\": open(\"$function_file\", \"r\").read(),
    \"meta\": {
        \"description\": \"$description\",
        \"manifest\": {
            \"requirements\": \"beeai-sdk\"
        }
    }
}))")

step_api_call "Creating function" $post_endpoint POST -d "$body"

# Make sure the function is toggled on
if [ "$(function_active $function_id)" == "false" ]
then
    step_api_call "Activating function" functions/id/$function_id/toggle POST
fi

# If Valves given, configure them
if [ "$valves" != "" ]
then
    step_api_call "Configuring function" functions/id/$function_id/valves/update POST -d"$valves"
fi

# Enable web search with duckduckgo
step_api_call "Enabling web search" configs/import POST \
    -d"{\"config\": $(api_call configs/export GET \
        | jq '.rag.web.search.enable = true' \
        | jq '.rag.web.search.engine = "duckduckgo"')}"
