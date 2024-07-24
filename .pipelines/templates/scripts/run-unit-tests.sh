#!/usr/bin/env bash

set -eoux pipefail

# A function called on exit to generate the JUnit and Cobertura XML files.
generate_results() {
    local total_failures
    local total_duration
    local total_skipped

    total_failures=$(echo "${status[@]}" | jq -MR 'split(" ") | map(select(.=="failed")) | length')
    total_duration=$(echo "${duration[@]}" | jq -s 'add')
    total_skipped=$(echo "${status[@]}" | jq -MR 'split(" ") | map(select(.=="skipped")) | length')

    cat <<EOF > "${LoggingDirectory}/JUnit.xml"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="1" failures="${total_failures}" errors="0" time="0">
    <testsuite name="SPDK Unit Tests" tests="${#status[@}]}" disabled="0" skipped="${total_skipped}" errors="0" failures="${total_failures}" time="${total_duration}">
        <testcase name="SPDK Unit Test Setup" status="${status["setup"]}" time="${duration["setup"]}">
            <system-out>
                <![CDATA[
${message["setup"]}
[[ATTACHMENT|unit-test-setup.log]]
]]>
            </system-out>
        </testcase>
        <testcase name="SPDK Unit Tests" status="${status["unit"]}" time="${duration["unit"]}">
            <system-out>
                <![CDATA[
${message["unit"]}
[[ATTACHMENT|unit-tests.log]]
]]>
            </system-out>
        </testcase>
        <testcase name="SPDK Unit Test Cleanup" status="${status["cleanup"]}" time="${duration["cleanup"]}">
            <system-out>
                <![CDATA[
${message["cleanup"]}
[[ATTACHMENT|unit-test-cleanup.log]]
]]>
            </system-out>
        </testcase>
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
set +x
command time --format="%e" --output="${LoggingDirectory}/unit-test-setup-time" "${SCRIPT_DIR}/unit-test/setup.sh" 2>&1 | tee "${LoggingDirectory}/unit-test-setup.log"
rc=$?
set -x
if [ $rc -ne 0 ]; then
    set_status "setup" "failed" "$(cat "${LoggingDirectory}/unit-test-setup-time")" "Setup failed."
    exit 1
fi

set_status "setup" "passed" "$(cat "${LoggingDirectory}/unit-test-setup-time")" "Setup succeeded."

# Run the unit tests.
set +x
command time --format="%e" --output="${LoggingDirectory}/unit-test-time" "${WorkingDirectory}/test/unit/unittest.sh" 2>&1 | tee "${LoggingDirectory}/unit-tests.log"
rc=$?
set -x
if [ $rc -ne 0 ]; then
    set_status "unit" "failed" "$(cat "${LoggingDirectory}/unit-test-time")" "Unit tests failed."
    exit 1
fi

set_status "unit" "passed" "$(cat "${LoggingDirectory}/unit-test-time")" "Unit tests passed."

# Cleanup the environment after the unit tests.
set +x
command time --format="%e" --output="${LoggingDirectory}/unit-test-cleanup-time" "${SCRIPT_DIR}/unit-test/cleanup.sh" 2>&1 | tee "${LoggingDirectory}/unit-test-cleanup.log"
rc=$?
set -x
if [ $rc -ne 0 ]; then
    set_status "cleanup" "failed" "$(cat "${LoggingDirectory}/unit-test-cleanup-time")" "Cleanup failed."
    exit 1
fi

set_status "cleanup" "passed" "$(cat "${LoggingDirectory}/unit-test-cleanup-time")" "Cleanup passed"

