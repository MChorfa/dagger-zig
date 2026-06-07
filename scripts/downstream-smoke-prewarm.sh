#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/downstream-smoke"
SDK_DIR="${FIXTURE_DIR}/vendor/dagger-sdk"

rm -rf "${SDK_DIR}"
mkdir -p "${SDK_DIR}"

copy_file() {
    local source_path="$1"
    local target_path="${SDK_DIR}/${source_path}"

    mkdir -p "$(dirname "${target_path}")"
    cp "${PROJECT_ROOT}/${source_path}" "${target_path}"
}

copy_tree() {
    local source_dir="$1"
    mkdir -p "${SDK_DIR}/${source_dir}"
    cp -R "${PROJECT_ROOT}/${source_dir}/." "${SDK_DIR}/${source_dir}/"
}

rm -f "${SDK_DIR}/LICENSE" "${SDK_DIR}/README.md"

copy_file "build.zig"
copy_file "build.zig.zon"
copy_tree "src"