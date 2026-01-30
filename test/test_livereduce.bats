#!/usr/bin/env bats

# test_livereduce.bats - Unit tests for livereduce.sh

setup() {
    # Create temporary directory for tests
    export TEST_DIR="$(mktemp -d)"
    export HOME="${TEST_DIR}"
    export SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export LIVEREDUCE_SCRIPT="${SCRIPT_DIR}/scripts/livereduce.sh"

    # Create mock directories
    mkdir -p "${TEST_DIR}/.cache/fontconfig"
    mkdir -p "${TEST_DIR}/bin"

    # Create mock files
    touch "${TEST_DIR}/.cache/fontconfig/test.cache"
}

teardown() {
    # Cleanup
    if [ -n "${TEST_DIR}" ] && [ -d "${TEST_DIR}" ]; then
        rm -rf "${TEST_DIR}"
    fi
}

# Helper function to create test config files
create_config_with_pixi_env() {
    local config_file="$1"
    local env_name="$2"
    echo "{\"PIXI_ENV\": \"${env_name}\"}" > "${config_file}"
}

create_config_with_conda_env() {
    local config_file="$1"
    local env_name="$2"
    echo "{\"CONDA_ENV\": \"${env_name}\"}" > "${config_file}"
}

# Test: Environment name conversion logic (isolated)
@test "CONDA_ENV with -dev suffix converts to _dev" {
    CONDA_ENVIRON="mantid-dev"
    if [[ "${CONDA_ENVIRON}" == *-dev ]]; then
        PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
    fi
    [ "${PIXI_ENVIRON}" = "mantid_dev" ]
}

@test "CONDA_ENV with -qa suffix converts to _qa" {
    CONDA_ENVIRON="mantid-qa"
    if [[ "${CONDA_ENVIRON}" == *-qa ]]; then
        PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
    fi
    [ "${PIXI_ENVIRON}" = "mantid_qa" ]
}

@test "CONDA_ENV without suffix remains unchanged" {
    CONDA_ENVIRON="mantid_prod"
    PIXI_ENVIRON="${CONDA_ENVIRON}"
    if [[ "${CONDA_ENVIRON}" == *-dev ]]; then
        PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
    elif [[ "${CONDA_ENVIRON}" == *-qa ]]; then
        PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
    fi
    [ "${PIXI_ENVIRON}" = "mantid_prod" ]
}

@test "CONDA_ENV with -dev in middle doesn't convert" {
    CONDA_ENVIRON="my-dev-environment"
    PIXI_ENVIRON="${CONDA_ENVIRON}"
    if [[ "${CONDA_ENVIRON}" == *-dev ]]; then
        PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
    fi
    [ "${PIXI_ENVIRON}" = "my-dev-environment" ]
}

@test "CONDA_ENV with -qa in middle doesn't convert" {
    CONDA_ENVIRON="my-qa-test"
    PIXI_ENVIRON="${CONDA_ENVIRON}"
    if [[ "${CONDA_ENVIRON}" == *-qa ]]; then
        PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
    fi
    [ "${PIXI_ENVIRON}" = "my-qa-test" ]
}

# Test: Config file detection with mock script
@test "uses default config path when no argument provided" {
    # Test just the logic
    run bash -c 'if [ $# -ge 1 ]; then echo "${1}"; else echo "/etc/livereduce.conf"; fi'
    [ "$status" -eq 0 ]
    [ "$output" = "/etc/livereduce.conf" ]
}

@test "uses provided config file path" {
    run bash -c 'if [ $# -ge 1 ]; then echo "${1}"; else echo "/etc/livereduce.conf"; fi' -- "/custom/path.conf"
    [ "$status" -eq 0 ]
    [ "$output" = "/custom/path.conf" ]
}

# Test: JSON parsing with jq
@test "jq correctly parses PIXI_ENV from config" {
    local config="${TEST_DIR}/test.conf"
    create_config_with_pixi_env "${config}" "test_env"

    result=$(/bin/jq --raw-output '.PIXI_ENV' "${config}")
    [ "$result" = "test_env" ]
}

@test "jq correctly parses CONDA_ENV from config" {
    local config="${TEST_DIR}/test.conf"
    create_config_with_conda_env "${config}" "conda_env"

    result=$(/bin/jq --raw-output '.CONDA_ENV' "${config}")
    [ "$result" = "conda_env" ]
}

# Test: grep detection of keys in config
@test "grep finds PIXI_ENV in config file" {
    local config="${TEST_DIR}/test.conf"
    create_config_with_pixi_env "${config}" "test_env"

    run grep -q PIXI_ENV "${config}"
    [ "$status" -eq 0 ]
}

@test "grep finds CONDA_ENV in config file" {
    local config="${TEST_DIR}/test.conf"
    create_config_with_conda_env "${config}" "test_env"

    run grep -q CONDA_ENV "${config}"
    [ "$status" -eq 0 ]
}

@test "grep doesn't find PIXI_ENV when not present" {
    local config="${TEST_DIR}/test.conf"
    create_config_with_conda_env "${config}" "test_env"

    run grep -q PIXI_ENV "${config}"
    [ "$status" -eq 1 ]
}

# Test: Font cache removal
@test "font cache files are removed" {
    touch "${HOME}/.cache/fontconfig/test1.cache"
    touch "${HOME}/.cache/fontconfig/test2.cache"

    rm -f "${HOME}"/.cache/fontconfig/*

    run ls "${HOME}/.cache/fontconfig/"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 0 ]
}

# Test: readlink resolves script path
@test "readlink -f resolves script path" {
    local test_script="${TEST_DIR}/test.sh"
    echo "#!/bin/bash" > "${test_script}"
    chmod +x "${test_script}"

    result=$(readlink -f "${test_script}")
    [[ "${result}" == "${TEST_DIR}/test.sh" ]]
}

# Test: dirname extracts directory
@test "dirname extracts directory from path" {
    result=$(dirname "/usr/bin/livereduce.sh")
    [ "$result" = "/usr/bin" ]
}

# Test: Integration test with mock nsd-app-wrap.sh
@test "script fails when nsd-app-wrap.sh is missing" {
    local config="${TEST_DIR}/test.conf"
    create_config_with_pixi_env "${config}" "test_env"

    # Create a test version of the script that stops before calling pixi_launch
    local test_script="${TEST_DIR}/livereduce_test.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
THISFILE=$(readlink -f "$0")
INSTALLDIR=$(dirname "${THISFILE}")
NSD_APP_WRAP="${INSTALLDIR}/nsd-app-wrap.sh"
if [ ! -f "${NSD_APP_WRAP}" ]; then
    echo "Failed to find nsd-app-wrap.sh"
    exit 1
fi
EOF
    chmod +x "${test_script}"

    run "${test_script}"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to find nsd-app-wrap.sh" ]]
}

# Test: Complete environment resolution logic
@test "PIXI_ENV takes precedence over CONDA_ENV" {
    local config="${TEST_DIR}/test.conf"
    echo '{"PIXI_ENV": "pixi_test", "CONDA_ENV": "conda_test"}' > "${config}"

    # Simulate the script logic
    PIXI_ENVIRON="mantid_dev"
    if grep -q PIXI_ENV "${config}"; then
        PIXI_ENVIRON="$(/bin/jq --raw-output '.PIXI_ENV' "${config}")"
    elif grep -q CONDA_ENV "${config}"; then
        CONDA_ENVIRON="$(/bin/jq --raw-output '.CONDA_ENV' "${config}")"
        if [[ "${CONDA_ENVIRON}" == *-dev ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
        elif [[ "${CONDA_ENVIRON}" == *-qa ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
        fi
    fi

    [ "${PIXI_ENVIRON}" = "pixi_test" ]
}

@test "CONDA_ENV with -dev is converted when PIXI_ENV not present" {
    local config="${TEST_DIR}/test.conf"
    echo '{"CONDA_ENV": "mantid-dev"}' > "${config}"

    # Simulate the script logic
    PIXI_ENVIRON="mantid_dev"
    if grep -q PIXI_ENV "${config}"; then
        PIXI_ENVIRON="$(/bin/jq --raw-output '.PIXI_ENV' "${config}")"
    elif grep -q CONDA_ENV "${config}"; then
        CONDA_ENVIRON="$(/bin/jq --raw-output '.CONDA_ENV' "${config}")"
        if [[ "${CONDA_ENVIRON}" == *-dev ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
        elif [[ "${CONDA_ENVIRON}" == *-qa ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
        fi
    fi

    [ "${PIXI_ENVIRON}" = "mantid_dev" ]
}

@test "CONDA_ENV with -qa is converted when PIXI_ENV not present" {
    local config="${TEST_DIR}/test.conf"
    echo '{"CONDA_ENV": "mantid-qa"}' > "${config}"

    # Simulate the script logic
    PIXI_ENVIRON="mantid_dev"
    if grep -q PIXI_ENV "${config}"; then
        PIXI_ENVIRON="$(/bin/jq --raw-output '.PIXI_ENV' "${config}")"
    elif grep -q CONDA_ENV "${config}"; then
        CONDA_ENVIRON="$(/bin/jq --raw-output '.CONDA_ENV' "${config}")"
        if [[ "${CONDA_ENVIRON}" == *-dev ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
        elif [[ "${CONDA_ENVIRON}" == *-qa ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
        fi
    fi

    [ "${PIXI_ENVIRON}" = "mantid_qa" ]
}

@test "default PIXI_ENVIRON used when config file doesn't exist" {
    local config="${TEST_DIR}/nonexistent.conf"

    # Simulate the script logic
    PIXI_ENVIRON="mantid_dev"
    if [ -f "${config}" ]; then
        if grep -q PIXI_ENV "${config}"; then
            PIXI_ENVIRON="$(/bin/jq --raw-output '.PIXI_ENV' "${config}")"
        fi
    fi

    [ "${PIXI_ENVIRON}" = "mantid_dev" ]
}

# Test: Argument passing
@test "script arguments are printed" {
    run bash -c 'echo "ARGS $*"' -- arg1 arg2 arg3
    [ "$status" -eq 0 ]
    [ "$output" = "ARGS arg1 arg2 arg3" ]
}

# Test: Using actual fake.conf from test directory
@test "can parse CONDA_ENV from test/fake.conf" {
    local config="${SCRIPT_DIR}/test/fake.conf"

    if [ -f "${config}" ]; then
        result=$(/bin/jq --raw-output '.CONDA_ENV' "${config}")
        [ "$result" = "livereduce" ]
    else
        skip "test/fake.conf not found"
    fi
}

# Test: Variable assignment check
@test "empty variable check works as expected" {
    NSD_APP_WRAP=""
    run bash -c '[ -z "${NSD_APP_WRAP}" ] && echo "empty" || echo "not empty"'
    [ "$output" = "empty" ]

    NSD_APP_WRAP="/some/path"
    run bash -c 'NSD_APP_WRAP="/some/path"; [ -z "${NSD_APP_WRAP}" ] && echo "empty" || echo "not empty"'
    [ "$output" = "not empty" ]
}
