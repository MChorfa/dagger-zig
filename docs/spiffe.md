# SPIFFE Integration

Workload identity support via SPIFFE/SPIRE.

## Overview

dagger-zig supports two backends:

| Backend | Status | Description |
|---------|--------|-------------|
| `ShelloutSource` | v0.1.0 working | Spawns `spire-agent` subprocess |
| `NativeWorkloadAPISource` | v0.1.1 | Pure Zig HTTP/2 + gRPC |

Both implement the same `SvidSource` interface. Upgrade from shellout to native with zero source changes.

## Shellout Backend (v0.1.0)

```zig
const spiffe = dagger.spiffe;

var shell = try spiffe.ShelloutSource.init(gpa, io, .{
    .expected_trust_domain = "ckodex.internal",  // hard-fail if agent lies
}, null);
defer shell.deinit();

const src = shell.source();
const svid = try src.fetchX509SVID(gpa);
defer svid.deinit();
```

### Limitations in v0.1.0

- `fetchX509SVID` — subprocess runs, DER parser is stub
- `fetchJWTSVID` / `fetchX509Bundle` — entirely stub
- `NativeWorkloadAPISource` — all network ops return `NotImplementedInV010`

## Native Backend (v0.1.1)

Implements the SPIFFE Workload API subset:

| RPC | Direction | v0.1.1 |
|-----|-----------|--------|
| FetchX509SVID | server-stream | Yes |
| FetchX509Bundles | server-stream | Yes |
| FetchJWTSVID | unary | Yes |
| FetchJWTBundles | server-stream | No (v0.2) |
| ValidateJWTSVID | unary | No (v0.2) |

### Protocol Stack

```
NativeWorkloadAPISource (facade)
├── WorkloadAPI (RPC dispatch)
├── gRPC client (length-prefix framing)
├── HTTP/2 subset
└── Unix domain socket (std.Io.net)
```

### Security Headers

Required request headers for SPIRE agent:

```
workload.spiffe.io: true
```

Absence is rejected by compliant agents.

## Trust Domain Enforcement

Always set `expected_trust_domain` in production:

```zig
var shell = try spiffe.ShelloutSource.init(gpa, io, .{
    .expected_trust_domain = "production.domain",
}, null);
```

This catches misconfigured-agent attacks.

## Registry Authentication

Mount short-lived credentials into a Container:

```zig
const auth = try dagger.spiffe_integration.spiffeRegistryAuth(
    ctx,
    "my-registry.example.com",
    svid,
);
const ctr = try ctx.dag().container()
    .withSecretVariable("REGISTRY_AUTH", auth);
```

## See Also

- [SPIFFE_IMPL.md](../SPIFFE_IMPL.md) — Full implementation specification
