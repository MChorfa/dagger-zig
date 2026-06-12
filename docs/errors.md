# Error Handling

The SDK uses Zig error sets to keep failure paths explicit and cheap.

## Error Sets

| Set | What it covers |
| --- | --- |
| `BuildError` | Client-side construction and serialization failures |
| `QueryError` | GraphQL transport and response failures |
| `ConnectError` | Engine bring-up and handshake failures |
| `PlatformError` | OS-specific socket and platform abstraction failures |

## Common `BuildError` Values

- `EmptySelection`
- `UnserializableArg`
- `SelectionTooDeep`
- `TooManyArguments`
- `RetryExceeded`
- `AlreadyExecuted`

## Common `QueryError` Values

- `TransportFailed`
- `HttpStatus`
- `MalformedResponse`
- `InvalidEnvelope`
- `DomainError`
- `CircuitOpen`

## Common `ConnectError` Values

- `SpawnFailed`
- `CliExited`
- `HandshakeFailed`
- `InvalidEnv`
- `DownloadFailed`
- `ShutdownFailed`

## Common Patterns

Use `try` to propagate failures:

```zig
const ctr = try client.dag().container();
const run = try ctr.from("alpine:latest");
```

Use `catch` when you want a fallback:

```zig
const client = dagger.connect(gpa, io, cfg) catch |err| {
    std.log.err("connect failed: {s}", .{@errorName(err)});
    return err;
};
```

Use `defer` to clean up owned memory and handles on error paths:

```zig
var span = try trace.Span.init(allocator, "build", .{});
defer span.deinit();
defer span.end();
```

## Domain Errors

GraphQL domain errors are carried separately from transport errors.
`QueryError.DomainError` tells you the request reached the engine and the engine
returned an application-level error. Inspect the client's stored domain error
for the payload.

## Guidance

- Match on the narrowest error set you can.
- Free owned memory before returning from a failure path.
- Treat `CircuitOpen` as a fast-fail signal, not a retry signal.

## Related Pages

- [Architecture](architecture.md)
- [Resilience Patterns](resilience.md)
- [Query Builder](query-builder.md)
