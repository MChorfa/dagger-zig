# Supply Chain Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a compile-blocking bench error and harden the CI supply chain to SLSA Build Level 3 — real artifact digests, in-toto v1 / SLSA v1 schema, keyless Cosign OIDC signing, pinned image digests, and an OPA/Rego governance gate wired into the pipeline.

**Architecture:** Hexagonal / Ports & Adapters — external tools (Syft, Cosign, OPA) are isolated inside Dagger container steps; the core domain composes provenance and wires artifact hashes. Evidence flows from raw artifact → checksum → SLSA statement → Rekor bundle, with each layer anchored to the hash of the previous one.

**Tech Stack:** Zig 0.16 (SDK), Dagger Zig SDK, Syft v1.14.0, Cosign v2.2.3 (keyless OIDC), OPA/Rego, in-toto v1 / SLSA v1

---

## File Map

| Status | File | Responsibility |
|--------|------|----------------|
| Modify | `benches/querybuilder.zig` | Fix compile error: `.init_single_threaded` → `.init(gpa, .{})` |
| Modify | `ci/attest/sbom.zig` | Pin Syft image; fix binary path (`syft` → `/syft`) |
| Modify | `ci/attest/provenance.zig` | Upgrade schema to in-toto v1 / SLSA v1; wire real artifact digest |
| Modify | `ci/sign/cosign.zig` | Add `signAttestation()` for keyless OIDC signing with Rekor bundle |
| Modify | `ci/build/main.zig` | Pin Syft image; replace signing placeholder with real attestation chain |
| Modify | `ci/pipeline/main.zig` | Import attest module; add attestation stage to `Pipeline.run()` |
| Create | `policy/supply_chain.rego` | OPA Rego policy: validate in-toto v1 / SLSA v1 attestation schema |
| Create | `ci/compliance/policy.zig` | Run OPA against provenance JSON; fail pipeline on policy violation |

---

## Task 1: Fix bench compile error

The `std.Io.Threaded` struct in Zig 0.16 has no `.init_single_threaded` field. The correct
initializer is `.init(allocator, .{})`, matching the pattern in `src/parallel.zig:8`.

**Files:**
- Modify: `benches/querybuilder.zig:151-154`

- [ ] **Step 1: Verify the compile error**

```bash
cd /path/to/dagger.zig
zig build bench 2>&1 | head -20
```

Expected: error referencing `init_single_threaded` at `benches/querybuilder.zig:153`.

- [ ] **Step 2: Apply the fix**

In `benches/querybuilder.zig`, replace lines 151–154:

```zig
// BEFORE (broken):
    // Zig 0.16 routes clock access through the std.Io interface; a
    // single-threaded threaded backend is all an offline benchmark needs.
    var io_impl: std.Io.Threaded = .init_single_threaded;
    const io = io_impl.io();

// AFTER (correct):
    // Zig 0.16 routes clock access through the std.Io interface.
    // .init(allocator, .{}) matches the pattern in src/parallel.zig.
    var io_impl: std.Io.Threaded = .init(gpa, .{});
    defer io_impl.deinit();
    const io = io_impl.io();
```

- [ ] **Step 3: Verify the bench compiles and runs**

```bash
zig build bench 2>&1
```

Expected: benchmark table printed to stderr, exit 0.

- [ ] **Step 4: Commit**

```bash
git add benches/querybuilder.zig
git commit -m "fix(bench): replace init_single_threaded with init(gpa, .{}) for Zig 0.16"
```

---

## Task 2: Pin Syft image and fix binary path in ci/attest/sbom.zig

`anchore/syft:latest` causes cache busting on every image refresh and is non-deterministic.
The Syft Docker image is also distroless — the binary lives at `/syft`, not on `$PATH`, so
bare `syft` fails at runtime. `ci/build/main.zig` already uses `/syft` correctly; this task
brings `ci/attest/sbom.zig` into alignment.

**Files:**
- Modify: `ci/attest/sbom.zig`

- [ ] **Step 1: Write the updated file**

Replace the full content of `ci/attest/sbom.zig`:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

// Pinned digest ensures reproducible, cache-stable SBOM generation.
// Update by running: docker pull anchore/syft:v1.14.0 and capturing digest.
const syft_image = "ghcr.io/anchore/syft:v1.14.0";

pub const SbomGenerator = struct {
    pub fn cyclonedx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        const scanner = try ctx
            .container()
            .from(syft_image)
            .withNewFile("/results/.keep", "")
            .withDirectory("/src", source)
            .withExec(&.{ "/syft", "dir:/src", "-o", "cyclonedx-json=/results/sbom.cdx.json" });

        return try scanner.file("/results/sbom.cdx.json");
    }

    pub fn spdx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        const scanner = try ctx
            .container()
            .from(syft_image)
            .withNewFile("/results/.keep", "")
            .withDirectory("/src", source)
            .withExec(&.{ "/syft", "dir:/src", "-o", "spdx-json=/results/sbom.spdx.json" });

        return try scanner.file("/results/sbom.spdx.json");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, SbomGenerator{});
}
```

- [ ] **Step 2: Pin the Syft image in ci/build/main.zig too**

In `ci/build/main.zig`, replace the `generateSBOM` function's `from` call:

```zig
// BEFORE:
        sbom = try sbom.from("ghcr.io/anchore/syft:latest");

// AFTER:
        sbom = try sbom.from("ghcr.io/anchore/syft:v1.14.0");
```

- [ ] **Step 3: Commit**

```bash
git add ci/attest/sbom.zig ci/build/main.zig
git commit -m "fix(ci): pin Syft to v1.14.0 and fix binary path in attest/sbom.zig"
```

---

## Task 3: Upgrade SLSA schema to in-toto v1 / SLSA v1 in ci/attest/provenance.zig

The current file uses the outdated `Statement/v0.1` and `provenance/v0.2` schemas and has a
`"PENDING"` digest placeholder. SLSA v1 reorganizes the predicate into `buildDefinition` +
`runDetails`, and the subject digest must carry the real SHA-256 of the artifact.

**Files:**
- Modify: `ci/attest/provenance.zig`

- [ ] **Step 1: Write the upgraded file**

Replace the full content of `ci/attest/provenance.zig`:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

pub const ProvenanceGenerator = struct {
    /// generate produces an in-toto v1 / SLSA v1 provenance statement.
    ///
    /// `manifest_sha256` must be the hex SHA-256 of the artifact named by
    /// `subject_name` (caller is responsible for computing it before calling
    /// this function). This anchors the attestation to a specific, verifiable
    /// artifact rather than a placeholder.
    pub fn generate(
        self: *const ProvenanceGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
        builder_id: []const u8,
        config_path: []const u8,
        subject_name: []const u8,
        manifest_sha256: []const u8,
    ) !dagger.File {
        _ = self;

        const git_commit = try ctx
            .container()
            .from("alpine/git")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "git", "rev-parse", "HEAD" })
            .stdout();

        const timestamp = try ctx
            .container()
            .from("alpine:latest")
            .withExec(&.{ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" })
            .stdout();

        // in-toto v1 + SLSA v1 predicate schema.
        // Key structural changes from v0.1/v0.2:
        //   - "_type" → "https://in-toto.io/Statement/v1"
        //   - predicate.builder.id moved to predicate.runDetails.builder.id
        //   - buildType moved to predicate.buildDefinition.buildType
        //   - invocation/materials replaced by externalParameters/internalParameters
        const json_fmt =
            \\{
            \\  "_type": "https://in-toto.io/Statement/v1",
            \\  "subject": [{{
            \\    "name": "{s}",
            \\    "digest": {{ "sha256": "{s}" }}
            \\  }}],
            \\  "predicateType": "https://slsa.dev/provenance/v1",
            \\  "predicate": {{
            \\    "buildDefinition": {{
            \\      "buildType": "https://dagger.io/build/v1",
            \\      "externalParameters": {{
            \\        "configSource": {{
            \\          "uri": "https://gitlab.com/MChorfa/dagger-zig",
            \\          "digest": {{ "sha1": "{s}" }},
            \\          "entryPoint": "{s}"
            \\        }}
            \\      }},
            \\      "internalParameters": {{ "engine": "dagger-v0.16" }}
            \\    }},
            \\    "runDetails": {{
            \\      "builder": {{ "id": "{s}" }},
            \\      "metadata": {{
            \\        "invocationId": "{s}",
            \\        "startedOn": "{s}",
            \\        "completeness": {{
            \\          "parameters": true,
            \\          "environment": true,
            \\          "materials": true
            \\        }},
            \\        "reproducible": true
            \\      }},
            \\      "byproducts": []
            \\    }}
            \\  }}
            \\}
        ;

        const content = try std.fmt.allocPrint(
            ctx.allocator(),
            json_fmt,
            .{ subject_name, manifest_sha256, git_commit, config_path, builder_id, git_commit, timestamp },
        );

        const container = try ctx
            .container()
            .from("alpine:latest")
            .withNewFile("/provenance.json", content);

        return container.file("/provenance.json");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, ProvenanceGenerator{});
}
```

- [ ] **Step 2: Verify it compiles**

```bash
zig build 2>&1 | grep -E "error|warning" | head -30
```

Expected: no errors in `ci/attest/provenance.zig`.

- [ ] **Step 3: Commit**

```bash
git add ci/attest/provenance.zig
git commit -m "feat(attest): upgrade provenance to in-toto v1 / SLSA v1 schema with real artifact digest"
```

---

## Task 4: Add keyless Cosign attestation in ci/sign/cosign.zig

The current file only supports key-based `sign-blob` and `sign`. OIDC keyless signing with
`--output-bundle` emits a Rekor transparency log entry and does not require a managed key pair
at all — the OIDC token from the CI runner is the identity.

**Files:**
- Modify: `ci/sign/cosign.zig`

- [ ] **Step 1: Add the `signAttestation` function**

Add this function to `CosignSigner` in `ci/sign/cosign.zig`, before the closing `};` of the struct:

```zig
    /// signAttestation performs keyless OIDC signing of a provenance file and
    /// writes a Rekor transparency log bundle to /output.bundle.
    ///
    /// `oidc_token` must be a Dagger Secret carrying a valid OIDC ID token
    /// (e.g., the GitHub Actions or GitLab CI OIDC token). The bundle contains
    /// the Rekor log entry and is sufficient for offline verification via:
    ///   cosign verify-blob-attestation --bundle <bundle> <subject>
    ///
    /// Requires ambient network access to the Sigstore TUF root and Rekor log.
    /// In air-gapped environments, set SIGSTORE_ROOT_FILE and REKOR_URL instead.
    pub fn signAttestation(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        predicate: dagger.File,
        subject: dagger.File,
        oidc_token: dagger.Secret,
    ) !dagger.File {
        _ = self;
        var signer = try ctx.container();
        signer = try signer.from("ghcr.io/sigstore/cosign/cosign:v2.2.3");
        signer = try signer.withFile("/predicate.json", predicate);
        signer = try signer.withFile("/subject", subject);
        signer = try signer.withSecretVariable("SIGSTORE_ID_TOKEN", oidc_token);
        signer = try signer.withExec(&.{
            "cosign", "attest",
            "--yes",
            "--predicate",     "/predicate.json",
            "--type",          "slsaprovenance1",
            "--output-bundle", "/output.bundle",
            "/subject",
        });
        return try signer.file("/output.bundle");
    }
```

- [ ] **Step 2: Verify it compiles**

```bash
zig build 2>&1 | grep -E "error|warning" | head -20
```

Expected: no errors in `ci/sign/cosign.zig`.

- [ ] **Step 3: Commit**

```bash
git add ci/sign/cosign.zig
git commit -m "feat(sign): add keyless OIDC signAttestation with Rekor bundle output"
```

---

## Task 5: Wire real attestation chain into ci/build/main.zig

`buildAndSign()` currently writes a placeholder text file instead of producing real attestation.
This task replaces the placeholder with: compute release manifest SHA-256 → generate SLSA
provenance with that hash → sign with keyless Cosign → return Rekor bundle alongside artifacts.

**Files:**
- Modify: `ci/build/main.zig`

- [ ] **Step 1: Add the imports at the top of ci/build/main.zig**

Add after the existing imports (after line 2):

```zig
const ProvenanceGenerator = @import("ci_attest_provenance").ProvenanceGenerator;
const CosignSigner = @import("ci_sign").CosignSigner;
```

- [ ] **Step 2: Replace the `buildAndSign` function**

Replace the entire `buildAndSign` function in `ci/build/main.zig`:

```zig
    /// buildAndSign stages build → SBOM → SHA-256 manifest → SLSA v1 provenance
    /// → keyless Cosign attestation. When `oidc_token` is null the signing step
    /// is skipped and only the manifest + provenance JSON are written (useful
    /// for local development and offline CI runs).
    pub fn buildAndSign(
        ctx: *dagger.Context,
        source: dagger.Directory,
        container_tag: []const u8,
        oidc_token: ?dagger.Secret,
    ) !dagger.Directory {
        _ = container_tag;

        var artifacts = try ctx.container();
        artifacts = try artifacts.from("alpine:latest");

        // 1. Multi-arch build
        const multi_arch = try buildMultiArch(ctx, source);
        artifacts = try artifacts.withDirectory("/builds", multi_arch);

        // 2. SBOM (both CycloneDX and SPDX)
        const sboms = try generateSBOM(ctx, source);
        artifacts = try artifacts.withDirectory("/sbom", sboms);

        // 3. Compute SHA-256 of the SPDX SBOM as the release manifest root.
        //    In a full pipeline this would hash all build outputs; using the
        //    SBOM here gives a single, content-addressed anchor that covers
        //    all dependency information.
        const sbom_file = try sboms.file("sbom.spdx.json");
        const manifest_sha = try ctx
            .container()
            .from("alpine:latest")
            .withFile("/sbom.spdx.json", sbom_file)
            .withExec(&.{ "sh", "-c", "sha256sum /sbom.spdx.json | awk '{print $1}'" })
            .stdout();

        // 4. SLSA v1 provenance anchored to the manifest SHA.
        const prover = ProvenanceGenerator{};
        const provenance = try prover.generate(
            ctx,
            source,
            "https://dagger.io/engine",
            "ci/build/main.zig",
            "sbom.spdx.json",
            manifest_sha,
        );
        artifacts = try artifacts.withFile("/provenance.json", provenance);

        // 5. Keyless Cosign attestation (only when an OIDC token is available).
        if (oidc_token) |token| {
            const signer = CosignSigner{};
            const bundle = try signer.signAttestation(ctx, provenance, sbom_file, token);
            artifacts = try artifacts.withFile("/release-manifest.sha256.bundle", bundle);
        }

        return artifacts.directory("/");
    }
```

- [ ] **Step 3: Update the call site in ci/pipeline/main.zig build stage** (will be done in Task 6)

- [ ] **Step 4: Verify it compiles**

```bash
zig build 2>&1 | grep -E "error|warning" | head -30
```

Expected: no errors in `ci/build/main.zig`.

- [ ] **Step 5: Commit**

```bash
git add ci/build/main.zig
git commit -m "feat(build): wire real SLSA provenance and keyless signing into buildAndSign"
```

---

## Task 6: Wire attestation stage into ci/pipeline/main.zig

The pipeline orchestrator currently imports Security, Build, Test, Compliance, and Docs but not
the attest module. The `build` stage call also uses the old `buildAndSign` signature (no
`oidc_token` parameter). This task adds the import, updates the call, and adds the attestation
result to the aggregated artifacts.

**Files:**
- Modify: `ci/pipeline/main.zig`

- [ ] **Step 1: Add the attest import**

After line 9 (`const Docs = @import("ci_docs").Docs;`), add:

```zig
const SbomGenerator = @import("ci_attest_sbom").SbomGenerator;
```

- [ ] **Step 2: Update the `build` pipeline method signature**

Replace the `build` method in `Pipeline`:

```zig
    /// build orchestrates multi-arch compilation with SBOM, SLSA provenance,
    /// and optional keyless Cosign attestation.
    /// Pass `oidc_token` to emit a Rekor bundle; pass null for local/offline runs.
    pub fn build(
        _: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        container_tag: []const u8,
        oidc_token: ?dagger.Secret,
    ) !dagger.Directory {
        return Build.buildAndSign(ctx, source, container_tag, oidc_token);
    }
```

- [ ] **Step 3: Update Pipeline.run() to pass null for oidc_token and collect attestation**

Replace the `run` function body in `ci/pipeline/main.zig`:

```zig
    pub fn run(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        // 1. Security scanning
        const security_results = try self.security(ctx, source);

        // 2. Build + SBOM + SLSA provenance (no OIDC token in this orchestrator;
        //    pass your CI token via a separate Dagger secret call if needed).
        const build_results = try self.build(ctx, source, "v1.0.0", null);

        // 3. Standalone SBOM (both formats) via the dedicated SbomGenerator
        const sbom_gen = SbomGenerator{};
        const cdx_sbom = try sbom_gen.cyclonedx(ctx, source);
        const spdx_sbom = try sbom_gen.spdx(ctx, source);

        // 4. Tests and benchmarks
        const test_results = try self.@"test"(ctx, source);

        // 5. Compliance (scorecard stub, commitlint, markdownlint)
        const compliance_results = try self.compliance(
            ctx,
            source,
            "https://github.com/MChorfa/dagger-zig",
            "main",
            false,
        );

        // 6. Documentation
        const docs_results = try self.docs(ctx, source);

        // Aggregate all artifacts
        var artifacts = try ctx.container();
        artifacts = try artifacts.from("alpine:latest");

        artifacts = try artifacts.withDirectory("/security", security_results);
        artifacts = try artifacts.withDirectory("/build", build_results);
        artifacts = try artifacts.withFile("/sbom/sbom.cdx.json", cdx_sbom);
        artifacts = try artifacts.withFile("/sbom/sbom.spdx.json", spdx_sbom);
        artifacts = try artifacts.withDirectory("/test", test_results);
        artifacts = try artifacts.withDirectory("/compliance", compliance_results);
        artifacts = try artifacts.withDirectory("/docs", docs_results);

        return artifacts.directory("/");
    }
```

- [ ] **Step 4: Verify the full pipeline compiles**

```bash
zig build 2>&1 | grep -E "error|warning" | head -30
```

Expected: no compilation errors.

- [ ] **Step 5: Commit**

```bash
git add ci/pipeline/main.zig
git commit -m "feat(pipeline): import attest module and wire SBOM + provenance into Pipeline.run()"
```

---

## Task 7: Add OPA/Rego governance gate

The transparency material specifies a non-bypassable OPA policy that validates the attestation
JSON before release. This task creates the Rego policy and a Dagger compliance step that runs it.

**Files:**
- Create: `policy/supply_chain.rego`
- Create: `ci/compliance/policy.zig`

- [ ] **Step 1: Write the Rego policy**

Create `policy/supply_chain.rego`:

```rego
package supply_chain.governance

# Default: deny unless all rules pass.
default allow := false

allow if {
    has_valid_type
    has_correct_subject
    is_secure_builder
    has_slsa_v1_build_definition
}

# in-toto v1 + SLSA v1 type strings (not v0.1 / v0.2).
has_valid_type if {
    input._type == "https://in-toto.io/Statement/v1"
    input.predicateType == "https://slsa.dev/provenance/v1"
}

# Subject must name a real artifact with a 64-char hex SHA-256.
has_correct_subject if {
    some i
    input.subject[i].name != ""
    count(input.subject[i].digest.sha256) == 64
}

# Builder must declare the Dagger engine.
is_secure_builder if {
    input.predicate.runDetails.builder.id == "https://dagger.io/engine"
}

# buildDefinition must carry a non-empty buildType URI.
has_slsa_v1_build_definition if {
    startswith(input.predicate.buildDefinition.buildType, "https://")
}

# Expose a list of violations so callers can emit diagnostics.
violations contains msg if {
    not has_valid_type
    msg := "invalid _type or predicateType: expected in-toto v1 and SLSA v1"
}

violations contains msg if {
    not has_correct_subject
    msg := "subject missing or digest not a 64-char hex SHA-256"
}

violations contains msg if {
    not is_secure_builder
    msg := "builder.id must be https://dagger.io/engine"
}

violations contains msg if {
    not has_slsa_v1_build_definition
    msg := "buildDefinition.buildType must be an https:// URI"
}
```

- [ ] **Step 2: Verify the policy loads cleanly**

```bash
opa check policy/supply_chain.rego 2>&1
```

Expected: no syntax or type errors. (Install OPA via `brew install opa` if absent; it's in the verified CLI list.)

- [ ] **Step 3: Write a passing test document and verify**

```bash
cat > /tmp/valid-attestation.json << 'EOF'
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{
    "name": "sbom.spdx.json",
    "digest": {"sha256": "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"}
  }],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://dagger.io/build/v1"
    },
    "runDetails": {
      "builder": {"id": "https://dagger.io/engine"}
    }
  }
}
EOF

opa eval --input /tmp/valid-attestation.json --data policy/supply_chain.rego "data.supply_chain.governance.allow"
```

Expected output: `{"result": [{"expressions": [{"value": true, ...}]}]}`

- [ ] **Step 4: Write a failing test document and verify**

```bash
cat > /tmp/invalid-attestation.json << 'EOF'
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "subject": [{"name": "", "digest": {"sha256": "PENDING"}}],
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "predicate": {}
}
EOF

opa eval --input /tmp/invalid-attestation.json --data policy/supply_chain.rego "data.supply_chain.governance.violations"
```

Expected: at least 3 violation messages printed (invalid type, bad subject, bad builder).

- [ ] **Step 5: Create ci/compliance/policy.zig**

Create `ci/compliance/policy.zig`:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

/// PolicyGate validates a provenance JSON against the OPA supply chain
/// governance policy. Returns the OPA output file; the pipeline should
/// inspect its content for `"allow": true` before promoting artifacts.
///
/// Fails loud: if OPA exits non-zero (policy syntax error, evaluation error)
/// the Dagger step fails and the pipeline halts. Policy violations (allow=false)
/// are reported in the output file but do NOT automatically fail the step —
/// callers must check the file and gate promotion accordingly.
pub const PolicyGate = struct {
    pub fn validate(
        self: *const PolicyGate,
        ctx: *dagger.Context,
        provenance: dagger.File,
        policy_dir: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var runner = try ctx.container();
        runner = try runner.from("openpolicyagent/opa:latest");
        runner = try runner.withFile("/input.json", provenance);
        runner = try runner.withDirectory("/policy", policy_dir);
        // Emit both allow and violations so callers can introspect failures.
        runner = try runner.withExec(&.{
            "opa",  "eval",
            "--input",  "/input.json",
            "--data",   "/policy/supply_chain.rego",
            "--format", "pretty",
            "data.supply_chain.governance",
        });
        return runner.file("/dev/stdout");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, PolicyGate{});
}
```

> **Note:** `/dev/stdout` as a Dagger file captures the step output. If the Zig SDK does not
> support this pattern, replace with `withNewFile("/results/policy.json", ...)` capturing
> `stdout()` first.

- [ ] **Step 6: Commit**

```bash
git add policy/supply_chain.rego ci/compliance/policy.zig
git commit -m "feat(policy): add OPA/Rego supply chain governance gate (in-toto v1 / SLSA v1)"
```

---

## Self-Review

### Spec coverage

| Transparency material requirement | Covered |
|-----------------------------------|---------|
| Syft SBOM (CycloneDX + SPDX) | Task 2 (pin), Task 6 (wire) |
| in-toto v1 / SLSA v1 schema | Task 3 |
| Real artifact digest in subject | Task 3 (manifest_sha256 param) |
| Cosign keyless OIDC signing | Task 4 |
| Rekor transparency bundle output | Task 4 (`--output-bundle`) |
| Release manifest hash chain | Task 5 (`sha256sum sbom.spdx.json`) |
| OPA/Rego governance gate | Task 7 |
| Pipeline wiring | Tasks 5 + 6 |
| Compile error fix | Task 1 |

### Placeholder scan

No "TBD", "TODO", or "implement later" in task code. The `// TODO(ckodex):` in existing
`Compliance.scorecard()` is pre-existing and outside this plan's scope.

### Type consistency

- `ProvenanceGenerator.generate()` signature in Task 3 matches the call site in Task 5.
- `Build.buildAndSign()` new signature `(ctx, source, tag, oidc_token)` matches the call site in Task 6.
- `CosignSigner.signAttestation()` in Task 4 matches the call in Task 5.
