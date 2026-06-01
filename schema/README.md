# Dagger API Schema Validation

This directory contains the Dagger API schema validation system for dagger-zig SDK conformance testing.

## Overview

The validation system provides:

1. **Schema Validation** (`validation.zig`) - Validates SDK types against official Dagger GraphQL API
2. **Conformance Vectors** (`conformance.zig`) - Test cases for API compliance
3. **Standalone Validator** (`validate_main.zig`) - CLI tool for running validations
4. **API Reference** (`dagger.api.md`) - Official Dagger GraphQL API documentation

## Usage

### Run All Validations

```bash
zig run schema/validate_main.zig
```

### Run Specific Validation

```bash
# Schema validation only
zig run schema/validate_main.zig --schema-only

# Conformance tests only
zig run schema/validate_main.zig --conformance-only

# Specific category
zig run schema/validate_main.zig --category=container_api
```

### List Test Categories

```bash
zig run schema/validate_main.zig --list-categories
```

## Test Categories

| Category        | Description                                             |
| --------------- | ------------------------------------------------------- |
| `core_types`    | Basic type existence (Container, Directory, File, etc.) |
| `container_api` | Container methods (from, withExec, file, etc.)          |
| `directory_api` | Directory methods (withNewFile, entries, export, etc.)  |
| `file_api`      | File methods (contents, size, export)                   |
| `secret_api`    | Secret methods (plaintext)                              |
| `service_api`   | Service methods (start, stop, endpoint)                 |
| `cache_api`     | Cache volume methods                                    |
| `query_api`     | Query fields (container, directory, git, http)          |
| `mutation_api`  | Mutation operations                                     |
| `module_api`    | Module-specific APIs                                    |

## Conformance Vectors

Each conformance vector defines:

- **Category** - Test grouping
- **Name** - Unique test identifier
- **Description** - What is being tested
- **Required** - Whether test must pass for compliance
- **Min API Version** - Minimum Dagger API version required

## Architecture

```
schema/
├── dagger.api.md          # Official Dagger GraphQL API reference
├── validation.zig         # Core validation logic
├── conformance.zig        # Conformance test vectors
├── validate_main.zig      # Standalone validator CLI
└── README.md             # This file
```

## Adding New Conformance Tests

1. Add test function in `conformance.zig`:

```zig
fn testMyNewFeature(allocator: Allocator) !bool {
    _ = allocator;
    // Return true if feature exists and works correctly
    return true;
}
```

1. Register in `conformance_vectors`:

```zig
.{
    .category = .container_api,
    .name = "container_my_new_feature",
    .description = "Container has myNewFeature() method",
    .test_fn = testMyNewFeature,
    .required = true,
    .min_api_version = "v0.11.0",
},
```

## CI Integration

Add to your CI pipeline:

```yaml
- name: Schema Validation
  run: zig run schema/validate_main.zig

- name: Core Types Conformance
  run: zig run schema/validate_main.zig --category=core_types

- name: Container API Conformance
  run: zig run schema/validate_main.zig --category=container_api
```

## Compliance Levels

- **Level 1** (Core): All `required=true` tests in `core_types`, `query_api`
- **Level 2** (Standard): Level 1 + `container_api`, `directory_api`, `file_api`
- **Level 3** (Full): All tests including `secret_api`, `service_api`, `cache_api`

## Maintenance

When Dagger releases a new API version:

1. Update `dagger.api.md` with new documentation
2. Add new types to `loadCoreSchema()` in `validation.zig`
3. Add new conformance vectors for new features
4. Update version constraints in test vectors
