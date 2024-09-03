################################################################################
# Helpers for setting up the unit test environment
################################################################################

## Constants ###################################################################

export REPO_DIR=$(cd $(dirname "${BASH_SOURCE[0]}")/.. && pwd)
export SCRIPT="$REPO_DIR/get-lm-desk.sh"

BASE_PATH="/usr/local/bin:/usr/bin:/bin"

## Helpers #####################################################################

#----
# Get the workdir for this test
#----
function workdir {
    export WORKDIR=${WORKDIR:=$(mktemp -d)}
    echo ${WORKDIR}
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
# Run a test with a temporary home
#----
function run_test {
    workdir
    local test_path=${TEST_PATH:-$BASE_PATH}
    PATH=$test_path HOME=$WORKDIR/home $SCRIPT $@
}

## Assertions ##################################################################

#----
# Make sure the given filename exists and is a file
#----
function file_exists {
    if ! [ -f "$1" ]
    then
        echo "File does not exist: $1"
        return 1
    fi
}

#----
# Make sure the given filename is executable
#----
function executable {
    if ! [ -x "$1" ]
    then
        echo "Not executable: $1"
        return 1
    fi
}