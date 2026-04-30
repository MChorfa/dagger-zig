# Error Handling

Error handling patterns in dagger-zig.

## Overview

Zig's error union types provide explicit error handling.

## Error Types

- `ConnectError` - Connection failures
- `ClientError` - Query failures
- `ModuleError` - Module runtime errors

## Best Practices

- Use `try` for propagating errors
- Use `catch` for handling specific errors
- Always free resources in error paths
