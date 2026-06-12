# Workload Identity

SPIFFE/SPIRE workload identity support is available behind the experimental
SPIFFE flag.

## Status

- Enable with `zig build -Dspiffe-experimental`
- Core SPIFFE APIs live in [SPIFFE Integration](spiffe.md)
- Dagger-specific helpers live in `src/spiffe/integration.zig`

## What It Covers

- X.509 SVID retrieval
- JWT-SVID retrieval
- mTLS-friendly identity flows
- Short-lived identity use inside Dagger module code

## When To Use It

Use workload identity when a pipeline needs to authenticate to external
services without static long-lived secrets.

## When Not To Use It

Do not treat SPIFFE as the default path for local development. If a pipeline
does not need external identity, keep it out of the build.

## Related Pages

- [SPIFFE Integration](spiffe.md)
- [Security Notes](compliance.md)
- [Examples](examples.md)
