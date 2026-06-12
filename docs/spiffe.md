# SPIFFE Integration

SPIFFE support is experimental and opt-in.

## Status

- Enable with `-Dspiffe-experimental`
- Core SPIFFE APIs live in `src/spiffe/`
- Dagger integration helpers live in `src/spiffe/integration.zig`
- The native Workload API path is present as a skeleton and still being hardened

## What the SPIFFE Layer Provides

- `SpiffeID` parsing and validation
- `X509SVID` and `JWTSVID` types
- `SvidSource` abstraction for fetching SVIDs
- Shellout-based source for existing SPIRE agent setups
- Integration helpers for registry auth and other Dagger workflows

## Typical Flow

1. Build with SPIFFE enabled.
2. Create a `ShelloutSource` or native source.
3. Fetch an SVID through the `SvidSource` abstraction.
4. Use the SVID in a Dagger integration helper or your own workload-identity flow.

## Example

```zig
const dagger = @import("dagger_sdk");
const spiffe = dagger.spiffe;

var shell = try spiffe.ShelloutSource.init(gpa, io, .{}, null);
defer shell.deinit();

const source = shell.source();
var svid = try source.fetchX509SVID(gpa);
defer svid.deinit(gpa);
```

## Notes

- `fetchX509SVID` and `fetchJWTSVID` are one-shot fetches.
- Rotation is not the default documented path yet; poll if you need refresh
  behavior today.
- The experimental boundary is intentional so the core SDK does not depend on
  SPIFFE unless the feature flag is enabled.

## Related Pages

- [Workload Identity](workload-identity.md)
- [Security Notes](compliance.md)
- [Examples](examples.md)
