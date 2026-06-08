#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/downstream-smoke"

cd "${PROJECT_ROOT}"

bash "scripts/downstream-smoke-prewarm.sh"

for path in \
    tests/fixtures/downstream-smoke/build.zig \
    tests/fixtures/downstream-smoke/build.zig.zon \
    tests/fixtures/downstream-smoke/dagger.json \
    tests/fixtures/downstream-smoke/main.zig \
    tests/fixtures/downstream-smoke/vendor/dagger-sdk/build.zig; do
    ignore_details="$(git check-ignore -v "${path}" || true)"
    if [[ -n "${ignore_details}" ]]; then
        ignore_source="${ignore_details%%:*}"
        if [[ "${ignore_source}" == *".gitignore" ]]; then
            echo "ERROR: downstream smoke fixture hidden by repository .gitignore: ${path}" >&2
            echo "       rule source: ${ignore_source}" >&2
            exit 1
        fi
    fi
done

cd "${FIXTURE_DIR}"
output="$(dagger call hello)"
if [[ "${output}" != "hello from downstream smoke" ]]; then
    echo "ERROR: downstream smoke call returned unexpected output: ${output}" >&2
    exit 1
fi

echo "downstream smoke ok"
