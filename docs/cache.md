# Cache Volumes

Cache volumes are the persistent storage primitive exposed by the generated
Dagger API.

## What They Are

`CacheVolume` represents named cache storage that can be mounted into
containers across runs.

Typical use cases:

- package manager caches
- compiler caches
- build artifact caches that should survive between pipeline runs

## Basic Flow

```zig
const cache = try client.dag().cacheVolume("npm-cache-v1");
const ctr_with_cache = try ctr.withMountedCache("/root/.npm", cache);
```

## Fail-Safe Behavior

The repository also has a cache fail-safe policy layer in
`src/core/cache_safe.zig`.

That layer is responsible for:

- deciding when cache should be used
- falling back to uncached work if cache fails under permissive policy
- tracking cache hit/miss/fallback metrics
- avoiding cache writes when policy says read-only

## Policy Modes

The fail-safe layer exposes policy modes such as:

- auto
- required
- disabled
- read-only

Use the strict modes only when cache availability is guaranteed.

## Example

```zig
const cache = try client.dag().cacheVolume("zig-global-cache");
const ctr_with_cache = try ctr.withMountedCache("/var/cache/zig", cache);
```

## Operational Guidance

- Keep cache keys stable when you want reuse.
- Change the cache name when you want a hard reset.
- Treat cache misses as normal; treat cache failures as policy decisions.

## Related Pages

- [Examples](examples.md)
- [Resilience Patterns](resilience.md)
- [Build Guide](build.md)
