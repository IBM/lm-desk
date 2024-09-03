################################################################################
# These unit tests test different ways of installing ollama
################################################################################

# Bring in the helpers
source $(dirname "${BASH_SOURCE[0]}")/helpers.sh

function test_install_using_curl_no_writable_path {
    run_test
    ollama_bin="$WORKDIR/home/.local/bin/ollama"
    file_exists $ollama_bin || fail
    executable $ollama_bin || fail
}

function test_install_using_curl_writable_path {
    workdir
    test_path=$WORKDIR/some/path
    mkdir -p $test_path
    TEST_PATH=$test_path:$BASE_PATH run_test <<< "Y"
    ollama_bin="$test_path/ollama"
    file_exists $ollama_bin || fail
    executable $ollama_bin || fail
}
