# Observability Guide

## Overview

The dagger-zig SDK provides observability through OpenTelemetry integration, structured logging, and health checking.

## OpenTelemetry Integration

### Configuration

```zig
const dagger = @import("dagger_sdk");
const std = @import("std");

pub fn main() !void {
    // Initialize OpenTelemetry with OTLP exporter
    var otel = try dagger.telemetry.init(.{
        .service_name = "my-dagger-module",
        .service_version = "1.0.0",
        .otlp_endpoint = "https://otel-collector.example.com:4317",
        .otlp_headers = &.{
            .{ "api-key", "${OTEL_API_KEY}" },
        },
    });
    defer otel.deinit();

    // All dagger operations are now traced
    const ctx = try dagger.Context.init();
    const container = try ctx.container().from("alpine:latest");
}
```

### Automatic Instrumentation

The SDK automatically traces:

- **Container operations**: `from`, `withExec`, `withFile`
- **Directory operations**: `withDirectory`, `entries`, `export`
- **File operations**: `contents`, `size`, `export`
- **Secret access**: (logged as redacted)
- **Module calls**: All function invocations
- **HTTP requests**: To Dagger engine

### Span Attributes

Standard attributes added to all spans:

| Attribute            | Description        | Example          |
| -------------------- | ------------------ | ---------------- |
| `dagger.operation`   | Operation type     | `container.from` |
| `dagger.image`       | Image reference    | `alpine:latest`  |
| `dagger.platform`    | Target platform    | `linux/amd64`    |
| `dagger.cache_hit`   | Cache status       | `true`           |
| `dagger.duration_ms` | Operation duration | `150`            |

### Custom Spans

```zig
const span = try dagger.telemetry.startSpan("custom-operation");
defer span.end();

try span.setAttribute("custom.key", "value");
try span.addEvent("milestone-reached", .{
    .{ "detail", "processing complete" },
});
```

## Structured Logging

### Log Levels

| Level   | Use Case                        |
| ------- | ------------------------------- |
| `error` | Failures requiring intervention |
| `warn`  | Degraded conditions, retries    |
| `info`  | Significant state changes       |
| `debug` | Detailed operation flow         |
| `trace` | Function entry/exit             |

### Configuration

```zig
const logger = try dagger.logging.init(.{
    .level = .info,
    .format = .json,  // or .pretty for development
    .output = std.io.getStdErr().writer(),
});

// Contextual logging
const child = logger.withContext(.{
    .{ "module", "ci-pipeline" },
    .{ "build_id", build_id },
});

try child.info("starting build", .{});
try child.warn("retrying operation", .{ .attempt = 3, .max_attempts = 5 });
```

### Log Output Example (JSON)

```json
{
  "timestamp": "2024-06-15T14:30:00Z",
  "level": "info",
  "message": "container build completed",
  "module": "ci-pipeline",
  "build_id": "abc123",
  "attributes": {
    "image": "golang:1.22",
    "duration_ms": 45000,
    "cache_hit": true
  },
  "trace_id": "4f9e5f3e5e4c4c7e9e9e9e9e9e9e9e9e",
  "span_id": "7e8e9f0a1b2c3d4e"
}
```

## Metrics

### Built-in Metrics

| Metric                       | Type      | Description                     |
| ---------------------------- | --------- | ------------------------------- |
| `dagger.operations.total`    | Counter   | Total operations executed       |
| `dagger.operations.duration` | Histogram | Operation latency               |
| `dagger.cache.hits`          | Counter   | Cache hit count                 |
| `dagger.cache.misses`        | Counter   | Cache miss count                |
| `dagger.secrets.accessed`    | Counter   | Secret access count (no values) |

### Custom Metrics

```zig
const counter = try dagger.metrics.createCounter("builds.completed");
try counter.increment(.{ .{ "status", "success" } });

const histogram = try dagger.metrics.createHistogram("build.duration");
try histogram.record(duration_ms);
```

## Health Checks

### Liveness Probe

```zig
// HTTP endpoint for Kubernetes liveness probe
const health = try dagger.health.init(.{
    .liveness_path = "/health/live",
    .port = 8080,
});

// SDK automatically reports:
// - 200: All systems operational
// - 503: Critical failure (e.g., can't connect to Dagger engine)
```

### Readiness Probe

```zig
try health.setReadinessCheck("engine-connection", struct {
    fn check() !bool {
        return dagger.ping();
    }
}.check);

try health.setReadinessCheck("spiffe-identity", struct {
    fn check() !bool {
        return spiffe.hasValidIdentity();
    }
}.check);
```

## Distributed Tracing

### Trace Context Propagation

```zig
// Extract trace context from incoming request
const parent_ctx = try dagger.telemetry.extractContext(
    request.headers.get("traceparent")
);

// Create child span with parent context
const span = try dagger.telemetry.startSpanWithContext(
    "process-request",
    parent_ctx
);

// Propagate to outgoing requests
const headers = try dagger.telemetry.injectContext(span.context());
try request.addHeaders(headers);
```

### Sampling Configuration

```zig
const sampler = try dagger.telemetry.Sampler.init(.{
    .strategy = .parent_based,
    .root_strategy = .{
        .rate_limiting = .{ .max_per_second = 100 },
    },
    .remote_parent_sampled = .always_on,
    .remote_parent_not_sampled = .always_off,
});
```

## Alerting

### Recommended Alerts

| Alert                 | Threshold    | Action           |
| --------------------- | ------------ | ---------------- |
| High error rate       | > 5% in 5m   | Page on-call     |
| Slow operations       | p99 > 30s    | Notify team      |
| Cache miss spike      | > 50% change | Investigate      |
| Engine unreachable    | Any failure  | Page immediately |
| Secret access anomaly | > 100/min    | Security review  |

### Prometheus Recording Rules

```yaml
# High error rate
- record: dagger:operation_error_rate_5m
  expr: |
    sum(rate(dagger_operations_total{status="error"}[5m]))
    /
    sum(rate(dagger_operations_total[5m]))

# P99 latency
- record: dagger:operation_latency_p99_5m
  expr: |
    histogram_quantile(0.99,
      sum(rate(dagger_operations_duration_bucket[5m])) by (le)
    )
```

## Troubleshooting

### Enable Debug Logging

```bash
# Environment variables
export DAGGER_LOG_LEVEL=debug
export DAGGER_TRACE=true
export OTEL_EXPORTER_OTLP_ENDPOINT=https://localhost:4317
```

### View Traces Locally

```bash
# Run Jaeger for local development
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  jaegertracing/all-in-one:1.50

# Configure SDK to export to local Jaeger
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

### Common Issues

| Issue              | Solution                                       |
| ------------------ | ---------------------------------------------- |
| Missing spans      | Check `OTEL_TRACES_EXPORTER` env var           |
| High cardinality   | Review custom attributes                       |
| Trace gaps         | Enable `OTEL_PROPAGATORS=tracecontext,baggage` |
| Performance impact | Use sampling for high-volume operations        |

## Compliance

| Framework        | Control           | Implementation                                   |
| ---------------- | ----------------- | ------------------------------------------------ |
| SOC 2 CC7.2      | System monitoring | OpenTelemetry traces, logs                       |
| ISO 27001 A.12.4 | Logging           | Structured JSON logs with tamper-proof transport |
| PCI DSS 10.2     | Audit trail       | All operations traced with user context          |
