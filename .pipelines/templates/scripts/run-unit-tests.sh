#!/usr/bin/env bash

set -eoux pipefail

# A function called on exit to generate the JUnit and Cobertura XML files.
generate_results() {
    local total_failures
    local total_duration
    local total_skipped

    total_tests="${#status[@]}"
    total_failures=$(echo "${status[@]}" | jq -MR 'split(" ") | map(select(.=="failed")) | length')
    total_duration=$(echo "${duration[@]}" | jq -s 'add')
    total_skipped=$(echo "${status[@]}" | jq -MR 'split(" ") | map(select(.=="skipped")) | length')

    declare -A testcase=()

    for test in "${!status[@]}"; do
        testcase[$test]=""
        if [ "${status[$test]}" == "failed" ]; then
            testcase[$test]+=$'\n'"            <failure message=\"\" type=\"failed\">${message[$test]}</failure>"
        fi
        if [ "${status[$test]}" != "skipped" ]; then
            testcase[$test]+=$'\n'"            <system-out><![CDATA[[[ATTACHMENT|$test-test.log]]]]></system-out>"
        fi
        if [ "${testcase[$test]}" != "" ]; then
            testcase[$test]+=$'\n        '
        fi
    done

    cat <<EOF > "${LoggingDirectory}/JUnit.xml"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="SPDK Unit Tests" tests="${total_tests}" skipped="${total_skipped}" failures="${total_failures}" time="${total_duration}">
    <testsuite name="SPDK Unit Tests" tests="${total_tests}" skipped="${total_skipped}" failures="${total_failures}" time="${total_duration}">
        <testcase name="SPDK Unit Test Setup" status="${status["setup"]}" time="${duration["setup"]}">${testcase["setup"]}</testcase>
        <testcase name="SPDK Unit Tests" status="${status["unit"]}" time="${duration["unit"]}">${testcase["unit"]}</testcase>
        <testcase name="SPDK Unit Test Cleanup" status="${status["cleanup"]}" time="${duration["cleanup"]}">${testcase["cleanup"]}</testcase>
    </testsuite>
</testsuites>
EOF

    if [[ -e "${UT_COVERAGE}/ut_cov_unit.info" ]]; then
        lcov_cobertura --output "${WorkingDirectory}/out/Cobertura.xml" --base-dir "${WorkingDirectory}" "${UT_COVERAGE}/ut_cov_unit.info"
    fi
}

# Updates the status variables for a give stage.
set_status() {
    stage="$1"
    this_status="$2"
    this_duration="$3"
    this_message="$4"

    status["${stage}"]="${this_status}"
    duration["${stage}"]="${this_duration}"
    message["${stage}"]="${this_message}"
}

if [ -z "${WorkingDirectory:-}" ]; then
    echo "\$WorkingDirectory was not set by the testing framework."
    exit 1
fi

if [ -z "${LoggingDirectory:-}" ]; then
    echo "\$LoggingDirectory was not set by the testing framework."
    exit 1
fi

mkdir -p "${LoggingDirectory}"
mkdir -p "${WorkingDirectory}/out"

export SCRIPT_DIR
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

export UT_COVERAGE="${WorkingDirectory}/out/ut_coverage"

if [ -z "$(which time || true)" ]; then
    apt-get update && apt-get install -y time
fi

# Set default values for the status variables.
declare -Agx status=(["setup"]="skipped" ["unit"]="skipped" ["cleanup"]="skipped")
declare -Agx duration=(["setup"]="0" ["unit"]="0" ["cleanup"]="0")
declare -Agx message=(["setup"]="Setup skipped." ["unit"]="Unit tests skipped." ["cleanup"]="Cleanup skipped.")

trap 'generate_results' ERR EXIT

# Setup the environment for the unit tests.
set +e
command time --quiet --format="%e" --output="${LoggingDirectory}/setup-test-time" "${SCRIPT_DIR}/unit-test/setup.sh" 2>&1 | tee "${LoggingDirectory}/setup-test.log"
rc=$?
set -e
if [ $rc -ne 0 ]; then
    set_status "setup" "failed" "$(cat "${LoggingDirectory}/setup-test-time")" "Setup failed."
    exit 1
fi

set_status "setup" "passed" "$(cat "${LoggingDirectory}/setup-test-time")" "Setup succeeded."

# Run the unit tests.
set +e
command time --quiet --format="%e" --output="${LoggingDirectory}/unit-test-time" "${WorkingDirectory}/test/unit/unittest.sh" 2>&1 | tee "${LoggingDirectory}/unit-test.log"
rc=$?
set -e
if [ $rc -ne 0 ]; then
    set_status "unit" "failed" "$(cat "${LoggingDirectory}/unit-test-time")" "Unit tests failed."
    exit 1
fi

set_status "unit" "passed" "$(cat "${LoggingDirectory}/unit-test-time")" "Unit tests passed."

# Cleanup the environment after the unit tests.
set +e
command time --quiet --format="%e" --output="${LoggingDirectory}/cleanup-test-time" "${SCRIPT_DIR}/unit-test/cleanup.sh" 2>&1 | tee "${LoggingDirectory}/cleanup-test.log"
rc=$?
set -e
if [ $rc -ne 0 ]; then
    set_status "cleanup" "failed" "$(cat "${LoggingDirectory}/cleanup-test-time")" "Cleanup failed."
    exit 1
fi

set_status "cleanup" "passed" "$(cat "${LoggingDirectory}/cleanup-test-time")" "Cleanup passed"

