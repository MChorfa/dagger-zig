# Repository Layout

This repo is easiest to think about in four clusters:

| Cluster | What lives here |
| --- | --- |
| Public SDK | `src/root.zig`, `src/querybuilder.zig`, `src/gen_sample.zig`, `src/c_api.zig` |
| Runtime core | `src/core/` for engine session handling, transport, resilience, cache safety, and secrets |
| Module + SPIFFE | `src/module/` and `src/spiffe/` for codegen/runtime dispatch and workload identity |
| Tooling + docs | `ci/`, `sdk/`, `codegen/`, `examples/`, `docs/` |

## Source of truth by area

| Area | Primary files |
| --- | --- |
| SDK entrypoint | `src/root.zig` |
| Query serialization | `src/querybuilder.zig` |
| Transport and session lifecycle | `src/core/engine.zig`, `src/core/cli_session.zig`, `src/core/graphql_client.zig` |
| Retry and breaker logic | `src/core/resilience.zig` |
| Cache safety | `src/core/cache_safe.zig` |
| Secrets and redaction | `src/core/secrets.zig` |
| Module dispatch | `src/module/dispatch.zig`, `src/module/typedef.zig`, `src/module/server.zig` |
| SPIFFE support | `src/spiffe/shellout.zig`, `src/spiffe/native.zig` |
| Self-hosting CI | `ci/main.zig` and the `ci/` module tree |
| SDK bootstrap | `sdk/main.go` |

## Contributor map

- `src/root.zig` for API surface changes
- `src/core/resilience.zig` for reliability changes
- `src/core/cache_safe.zig` for cache policy changes
- `src/core/secrets.zig` for secret handling changes
- `ci/main.zig` for self-hosting validation
- `src/c_api.zig` for FFI changes
