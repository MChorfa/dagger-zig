# Repository Layout

```
dagger.zig/
├── src/
│   ├── root.zig            Public surface — dagger.connect, Client, types
│   ├── querybuilder.zig    Lazy Selection chain → GraphQL serializer
│   ├── gen_sample.zig      Hand-written Container/Directory/File API
│   ├── c_api.zig           C FFI (libdagger.{a,so,dylib})
│   └── core/
│       ├── engine.zig        CLI session lifecycle, env parsing
│       ├── cli_session.zig   Subprocess spawn, handshake read
│       ├── graphql_client.zig HTTP transport, JSON serialize
│       ├── config.zig        Timeouts, feature flags
│       ├── resilience.zig    Retry policy, circuit breaker, jitter
│       ├── cache_safe.zig    CacheFailSafe policies
│       └── secrets.zig       Secret registry + scrubber
│
├── src/module/
│   ├── dispatch.zig        Comptime method table + invoker shims
│   ├── typedef.zig         Zig type → Dagger TypeDef mapping
│   ├── server.zig          JSON-RPC stdin/stdout loop
│   └── serde.zig           Arg/return serialize for call framing
│
├── src/spiffe/
│   ├── id.zig              SPIFFE ID parser
│   ├── svid.zig            X509SVID / JWTSVID types
│   ├── source.zig          SvidSource vtable interface
│   ├── shellout.zig        ShelloutSource (v0.1.0 working backend)
│   └── native.zig          NativeWorkloadAPISource (v0.1.1)
│
├── ci/
│   └── main.zig            Self-hosting CI pipeline (Zig Dagger module)
│
├── sdk/
│   ├── main.go             Go bootstrap for Dagger engine integration
│   ├── runtime/
│   │   └── README.md       Container contract for module runtime
│   └── codegen/
│       └── README.md       Per-module codegen plan
│
├── codegen/
│   └── src/
│       └── emit.zig        Standalone emitter (full schema → gen.zig)
│
├── examples/
│   ├── first-pipeline/
│   ├── parallel/
│   └── c-client/
│
├── include/
│   └── dagger.h            C header for libdagger
│
└── docs/                     GitBook documentation
    ├── README.md
    ├── SUMMARY.md
    └── ...
```

## Key Files for Contributors

| File | Purpose |
|------|---------|
| `src/root.zig` | Public API surface |
| `src/core/resilience.zig` | Production resilience patterns |
| `src/core/cache_safe.zig` | Cache fail-safe |
| `src/core/secrets.zig` | Security architecture |
| `ci/main.zig` | Self-hosting proof |
| `src/c_api.zig` | FFI safety |
