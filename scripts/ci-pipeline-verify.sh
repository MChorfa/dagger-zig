#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${PROJECT_ROOT}"

if ! grep -q '"source": "../../sdk"' "ci/pipeline/dagger.json"; then
    echo "ERROR: full CI module is not pinned to the repository SDK source" >&2
    exit 1
fi

functions_output="$(dagger functions -m ./ci/pipeline)"
printf '%s\n' "${functions_output}" | grep -q '^run[[:space:]]'
dagger call -m ./ci/pipeline run --arg-0 .

echo "full ci ok"