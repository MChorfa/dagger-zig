# API Reference

## Client

### `dagger.connect(allocator, io, options) !Client`

Connect to Dagger engine via three-tier handshake.

```zig
var client = try dagger.connect(gpa, io, .{
    .connect_timeout_ms = 30000,
});
defer client.close();
```

### `client.dag() Query`

Get root query builder for fluent API chaining.

```zig
const ctr = try client.dag()
    .container()
    .from("alpine");
```

### `client.close()`

Release all resources. Arena is freed; all handles invalidated.

## Container

### `container().from(image) Container`

Create container from image reference.

### `withExec(args) Container`

Execute command, return new container with layer.

```zig
const ctr2 = try ctr1.withExec(&.{"go", "build", "./..."});
```

### `stdout() []const u8`

Capture stdout as string. Caller must free.

```zig
const output = try ctr.stdout();
defer gpa.free(output);
```

### `withDirectory(path, dir) Container`

Mount directory into container.

```zig
const ctr = try ctr.withDirectory("/src", source);
```

### `withSecretVariable(name, secret) Container`

Inject secret as environment variable.

```zig
const secret = try ctx.dag().setSecret("API_KEY", apiKeyValue);
const ctr = try ctr.withSecretVariable("API_KEY", secret);
```

## Directory

### `directory() Directory`

Create empty directory.

### `withNewFile(path, content) Directory`

Add new file with content.

```zig
const dir = try dir.withNewFile("main.go", sourceCode);
```

## Secret

### `setSecret(name, plaintext) Secret`

Register secret for scrubbing.

```zig
const secret = try ctx.dag().setSecret("TOKEN", token);
```

## CacheVolume

### `cacheVolume(name) CacheVolume`

Get or create named cache volume.

```zig
const cache = try ctx.dag().cacheVolume("go-mod-cache");
const ctr = try ctr.withMountedCache("/go/pkg/mod", cache);
```
