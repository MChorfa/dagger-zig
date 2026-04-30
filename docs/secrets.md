# Secret Management

Guide to handling secrets securely in dagger-zig.

## Overview

Secrets are mounted as files in containers and never exposed in logs.

## Usage

See [examples/secrets](../examples/secrets/) for a working example.

## Best Practices

- Use environment variables for local development
- Use proper secret management (Vault, 1Password) in production
- Never hardcode secrets in source code
