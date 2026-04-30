# Migrating to dagger-zig

Guide for developers coming from Go or Python SDKs.

## Quick Comparison

| Feature | Go SDK | Python SDK | Zig SDK |
|---------|--------|------------|---------|
| **Async** | `ctx` + channels | `async`/`await` | `std.Io.async` |
| **Memory** | GC | GC | Manual + arenas |
| **Error handling** | `if err != nil` | Exceptions | `try`/`catch` |
| **Type safety** | Runtime | Runtime | Compile-time |
| **Binary size** | ~10MB | ~50MB+ | ~1MB |

## Container Operations

### Go SDK
```go
out, err := client.Container().
    From("alpine").
    WithExec([]string{"echo", "hello"}).
    Stdout(ctx)
```

### Python SDK
```python
out = await (
    client.container()
    .from_("alpine")
    .with_exec(["echo", "hello"])
    .stdout()
)
```

### Zig SDK
```zig
const out = try client.dag()
    .container()
    .from("alpine")
    .withExec(&.{"echo", "hello"})
    .stdout();
defer gpa.free(out);
```

**Key differences:**
- `&.` instead of `[]string{}` or list
- `.dag()` required to get root Query
- `defer gpa.free(out)` for cleanup

## Directory Operations

### Go SDK
```go
dir := client.Host().Directory(".")
ctr := client.Container().
    From("node").
    WithDirectory("/src", dir)
```

### Python SDK
```python
dir = client.host().directory(".")
ctr = (client.container()
    .from_("node")
    .with_directory("/src", dir))
```

### Zig SDK
```zig
const dir = try client.dag()
    .host()
    .directory(".");
const ctr = try client.dag()
    .container()
    .from("node")
    .withDirectory("/src", dir);
```

**Key differences:**
- `dag()` instead of direct client access
- No method chaining with dots in Zig (each call returns new value)

## Secrets

### Go SDK
```go
secret := client.SetSecret("api-key", os.Getenv("API_KEY"))
ctr := client.Container().
    From("alpine").
    WithSecretVariable("API_KEY", secret)
```

### Python SDK
```python
secret = client.set_secret("api-key", os.environ["API_KEY"])
ctr = (client.container()
    .from_("alpine")
    .with_secret_variable("API_KEY", secret))
```

### Zig SDK
```zig
const secret = try client.dag()
    .setSecret("api-key", api_key);
const ctr = try client.dag()
    .container()
    .from("alpine")
    .withSecret("/run/secrets/api-key", secret);
```

**Key differences:**
- Secrets mounted as files in Zig (more secure)
- No `withSecretVariable` equivalent (use file mounting)

## Error Handling

### Go SDK
```go
out, err := ctr.Stdout(ctx)
if err != nil {
    return err
}
fmt.Println(out)
```

### Python SDK
```python
try:
    out = await ctr.stdout()
    print(out)
except dagger.DaggerError as e:
    print(f"Error: {e}")
```

### Zig SDK
```zig
const out = ctr.stdout() catch |err| {
    std.log.err("Failed: {}", .{err});
    return err;
};
std.debug.print("{s}\n", .{out});
```

**Key differences:**
- `try` is explicit error propagation
- `catch` blocks for handling
- No exceptions in Zig

## Memory Management

### Go/Python
Automatic garbage collection - no cleanup needed.

### Zig
```zig
const gpa = init.gpa;

// Allocate
const result = try someOperation(gpa);

// Must free when done
defer gpa.free(result);

// Or use arena for temp allocations
var arena_state = std.heap.ArenaAllocator.init(gpa);
defer arena_state.deinit();
const arena = arena_state.allocator();
```

**Critical:** Forgetting `defer gpa.free()` causes memory leaks!

## Module Authoring

### Go SDK
```go
type MyModule struct {}

func (m *MyModule) Build(ctx context.Context, source *dagger.Directory) (*dagger.Container, error) {
    return dag.Container().From("golang").WithDirectory("/src", source), nil
}
```

### Python SDK
```python
@dagger.object_type
class MyModule:
    @dagger.function
    async def build(self, source: dagger.Directory) -> dagger.Container:
        return await dag.container().from_("golang").with_directory("/src", source)
```

### Zig SDK
```zig
const MyModule = struct {
    pub fn build(
        self: *const MyModule,
        ctx: *dagger.module.Context,
        source: dagger.Directory,
    ) !dagger.Container {
        _ = self;
        return ctx.dag()
            .container()
            .from("golang")
            .withDirectory("/src", source);
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

**Key differences:**
- Zig modules are structs with methods
- First param is `self`, second is `ctx`
- `main` calls `serve()` to start module runtime

## Common Patterns

### Building and Publishing

**Go:**
```go
ctr := client.Container().From("golang").WithExec([]string{"go", "build"})
_, err := ctr.Publish(ctx, "myimage:latest")
```

**Zig:**
```zig
const ctr = try client.dag()
    .container()
    .from("golang")
    .withExec(&.{"go", "build"});
const digest = try ctr.publish("myimage:latest");
defer gpa.free(digest);
```

### Running Tests

**Go:**
```go
ctr := client.Container().From("golang").WithExec([]string{"go", "test"})
out, _ := ctr.Stdout(ctx)
```

**Zig:**
```zig
const out = try client.dag()
    .container()
    .from("golang")
    .withExec(&.{"go", "test"})
    .stdout();
defer gpa.free(out);
```

## Tips for Success

1. **Always use `defer gpa.free()`** for strings returned by Dagger
2. **Start with `dag()`** - all operations begin there
3. **Handle errors with `try`** - propagate or handle explicitly
4. **Use arenas** for temporary allocations in loops
5. **Run `zig fmt`** - auto-formatting is your friend
6. **Check build errors** - Zig's compiler catches issues early

## Resources

- [Go SDK → Zig Cheatsheet](https://example.com/cheatsheet) (coming soon)
- [Zig Language Tour](https://ziglang.org/learn/)
- [dagger-zig Examples](../examples/)
