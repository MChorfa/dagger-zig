# C API

The C ABI exists in `src/c_api.zig`, but it is still experimental and disabled
from the default build.

## Status

- Source is present
- Build step is commented out in `build.zig`
- The generated header lives at [include/dagger.h](../include/dagger.h)
- The default SDK path remains Zig-first

## What It Provides

- C-compatible handles for core SDK objects
- Thread-local error reporting
- Explicit ownership for returned strings and handles

## What It Does Not Provide Yet

- A promoted default build target
- A stable long-term ABI guarantee
- A production-ready release story separate from the Zig SDK path

## Guidance

Use the C API only when you need to integrate with a C or C++ host and can
accept the experimental boundary.

## Related Pages

- [Architecture](architecture.md)
- [Module Authoring](module-authoring.md)
- [Roadmap](roadmap.md)
