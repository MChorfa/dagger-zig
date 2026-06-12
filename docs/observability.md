# Observability

The observability story is built from three pieces:

- traces for operation timing and engine interaction
- structured logs for human and machine consumption
- metrics and health checks for runtime monitoring

## Tracing

Use OpenTelemetry-style spans when you need to understand how a pipeline moved
through the engine.

```zig
const dagger = @import("dagger_sdk");
const std = @import("std");

pub fn main() !void {
    var otel = try dagger.telemetry.init(.{
        .service_name = "my-dagger-module",
        .service_version = "1.0.0",
        .otlp_endpoint = "https://otel-collector.example.com:4317",
        .otlp_headers = &.{
            .{ "api-key", "${OTEL_API_KEY}" },
        },
    });
    defer otel.deinit();

    const span = try dagger.telemetry.startSpan("build-step");
    defer span.end();

    try span.setAttribute("step", "container.from");
}
```

## Logging

Keep logs structured and low-cardinality. That makes them useful in CI and in
production.

| Level | Use |
| --- | --- |
| `error` | Failure requiring intervention |
| `warn` | Degraded condition or retry |
| `info` | State changes worth keeping |
| `debug` | Detailed flow for troubleshooting |
| `trace` | Very chatty step-by-step inspection |

```zig
const logger = try dagger.logging.init(.{
    .level = .info,
    .format = .json,
    .output = std.io.getStdErr().writer(),
});

try logger.info("starting build", .{});
```

## Metrics

Track the few things you actually plan to watch.

| Metric | Meaning |
| --- | --- |
| `dagger.operations.total` | Total operations |
| `dagger.operations.duration` | Latency |
| `dagger.cache.hits` | Cache reuse |
| `dagger.cache.misses` | Cache misses |

## Health checks

Health checks should tell you whether the SDK can still talk to the engine.

```zig
const health = try dagger.health.init(.{
    .liveness_path = "/health/live",
    .port = 8080,
});
```

## Troubleshooting

| Symptom | First check |
| --- | --- |
| Missing spans | `OTEL_TRACES_EXPORTER` and endpoint config |
| Trace gaps | Propagators and exporter connectivity |
| High cardinality | Custom attributes |
| Slow telemetry | Sampling and exporter load |

## Compliance note

Observability data is useful evidence, but it is not itself a certification or
attestation. See [Compliance](compliance.md) for the release-provenance story.
