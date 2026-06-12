# Resilience Patterns

`src/core/resilience.zig` is where retry and circuit-breaker behavior lives.
The docs here describe the behavior the SDK actually implements.

## Retry Policy

`RetryPolicy` controls how failed GraphQL requests are retried:

- `max_retries`
- `initial_backoff_ms`
- `max_backoff_ms`
- `backoff_multiplier`
- `jitter_factor`
- `is_retryable`

Default policy:

- 3 retries
- 100ms initial backoff
- 5s max backoff
- 2x multiplier
- 10% jitter

## Circuit Breaker

`CircuitBreaker` fails fast after repeated failures and recovers through
half-open probing.

States:

- `closed`
- `open`
- `half_open`

The breaker:

- opens after the configured failure threshold
- skips requests while open
- probes again after the skip counter is reached
- closes after enough successful probes

## Resilient Execution

`ResilientExecutor.execute()` combines the retry policy and circuit breaker:

```zig
var executor = resilience.ResilientExecutor{
    .policy = .{},
    .breaker = &breaker,
    .io = io,
};

const result = try executor.execute(u32, struct {
    fn run() errs.QueryError!u32 {
        return 42;
    }
}.run);
```

Behavior:

- non-retryable errors return immediately
- retryable errors back off with jitter
- the breaker records success or failure for each attempt
- canceled sleeps are ignored so retries remain best-effort

## Client Configuration

Connection-time config chooses the policy:

```zig
var client = try dagger.connect(gpa, io, .{
    .retry_policy = resilience.RetryPolicy.conservative(),
    .enable_circuit_breaker = true,
});
```

Use conservative settings for CI and aggressive settings only when the network
is genuinely unstable.

## Operational Guidance

- Retry is for transient transport problems, not domain errors.
- Circuit breaking should fail fast rather than hide outages.
- Keep retry windows short in CI so failures surface quickly.
- Treat retry metrics as diagnostics, not as a substitute for fixing the root cause.

## Related Pages

- [Async Patterns](async-patterns.md)
- [Error Handling](errors.md)
- [Architecture](architecture.md)
