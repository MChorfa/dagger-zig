#!/usr/bin/env bash
# Verify a published dagger-zig release: SLSA Build L3 provenance, GitHub
# attestation, and keyless cosign signatures for every release tarball.
#
# Usage:
#   scripts/release-verify.sh [tag]        # tag defaults to the latest release
#   REPO=owner/name scripts/release-verify.sh v0.3.1
#
# Requires: gh, cosign, slsa-verifier (the script reports which are missing).
set -euo pipefail

REPO="${REPO:-MChorfa/dagger-zig}"
OIDC_ISSUER="https://token.actions.githubusercontent.com"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1 (install it to run this check)"; return 1; }; }

TAG="${1:-}"
if [ -z "${TAG}" ]; then
  need gh || exit 1
  TAG="$(gh release view --repo "${REPO}" --json tagName -q .tagName)"
fi
echo "Verifying ${REPO} release ${TAG}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
cd "${WORK}"

need gh || exit 1
gh release download "${TAG}" --repo "${REPO}" --clobber
echo

CERT_IDENTITY="https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/${TAG}"
fail=0

if [ -f checksums.sha256 ]; then
  if sha256sum -c checksums.sha256 >/dev/null 2>&1; then
    echo "   ✅ aggregate checksums"
  else
    echo "   ❌ aggregate checksums FAILED"
    fail=1
  fi
else
  echo "   ❌ missing checksums.sha256"
  fail=1
fi

if [ -f release-manifest.sha256 ]; then
  sbom_sha="$(sha256sum sbom.spdx.json | awk '{print $1}')"
  manifest_sha="$(tr -d ' \t\r\n' < release-manifest.sha256)"
  if [ "${sbom_sha}" = "${manifest_sha}" ]; then
    echo "   ✅ release manifest checksum"
  else
    echo "   ❌ release manifest checksum FAILED"
    fail=1
  fi

  if [ -f release-manifest.sha256.bundle ] && need cosign; then
    if cosign verify-blob \
        --bundle release-manifest.sha256.bundle \
        --certificate-identity "${CERT_IDENTITY}" \
        --certificate-oidc-issuer "${OIDC_ISSUER}" \
        release-manifest.sha256 >/dev/null 2>&1; then
      echo "   ✅ release manifest bundle"
    else
      echo "   ❌ release manifest bundle FAILED"
      fail=1
    fi
  else
    echo "   ❌ missing release-manifest.sha256.bundle"
    fail=1
  fi
else
  echo "   ❌ missing release-manifest.sha256"
  fail=1
fi

for f in *.tar.gz; do
  [ -e "${f}" ] || { echo "no tarballs found in release ${TAG}"; exit 1; }
  echo "── ${f}"

  # 1) SLSA Build L3 provenance
  if need slsa-verifier; then
    if slsa-verifier verify-artifact "${f}" \
        --provenance-path multiple.intoto.jsonl \
        --source-uri "github.com/${REPO}" --source-tag "${TAG}" >/dev/null 2>&1; then
      echo "   ✅ SLSA L3 provenance"
    else
      echo "   ❌ SLSA L3 provenance FAILED"; fail=1
    fi
  fi

  # 2) GitHub-native attestation
  if need gh; then
    if gh attestation verify "${f}" --repo "${REPO}" >/dev/null 2>&1; then
      echo "   ✅ GitHub attestation"
    else
      echo "   ❌ GitHub attestation FAILED"; fail=1
    fi
  fi

  # 3) Keyless cosign signature
  if need cosign; then
    if [ -f "${f}.bundle" ] && cosign verify-blob \
        --bundle "${f}.bundle" \
        --certificate-identity "${CERT_IDENTITY}" \
        --certificate-oidc-issuer "${OIDC_ISSUER}" \
        "${f}" >/dev/null 2>&1; then
      echo "   ✅ cosign signature"
    else
      echo "   ❌ cosign signature FAILED"; fail=1
    fi
  fi
done

echo
if [ "${fail}" -eq 0 ]; then
  echo "All checks passed for ${TAG}."
else
  echo "One or more checks failed for ${TAG}." >&2
  exit 1
fi
