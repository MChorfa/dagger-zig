# SPIFFE Integration

**Status:** Experimental — Enable with `-Dspiffe-experimental` build flag

SPIFFE (Secure Production Identity Framework for Everyone) workload identity support.

## Overview

The SPIFFE subsystem provides workload attestation and short-lived SVID (SPIFFE Verifiable Identity Document) issuance for authenticating to external services.

## Features

- Workload API client for fetching SVIDs
- Automatic certificate rotation
- mTLS authentication helpers

## Usage

Build with SPIFFE support enabled:

```bash
zig build -Dspiffe-experimental
```

## Status

This feature is experimental and the API may change in future releases.
