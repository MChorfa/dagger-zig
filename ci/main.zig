const std = @import("std");
const dagger = @import("dagger_sdk");

const HermeticBuilder = @import("build/hermetic.zig").HermeticBuilder;
const ProvenanceGenerator = @import("attest/provenance.zig").ProvenanceGenerator;
const SbomGenerator = @import("attest/sbom.zig").SbomGenerator;
const VulnerabilityScanner = @import("scan/vulnerability.zig").VulnerabilityScanner;
const CosignSigner = @import("sign/cosign.zig").CosignSigner;
const SchemaValidator = @import("../schema/main.zig").SchemaValidator;
const MarkdownLinter = @import("markdown.zig").MarkdownLinter;

pub const CiPipeline = struct {
    pub fn lint(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        const runner = try ctx.pipeline("code-quality-lint")
            .container()
            .from("alpine:latest")
            .withExec(&.{ "apk", "add", "--no-cache", "zig" })
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "zig", "fmt", "--check", "src/" });

        const output = try runner.stdout();
        return try ctx.directory().withNewFile("lint-output.txt", output);
    }

    /// Lint markdown documentation
    pub fn lintDocs(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        const linter = MarkdownLinter{};
        return try linter.fullCheck(ctx, source);
    }

    /// Build documentation site for GitHub Pages
    pub fn buildDocs(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;

        // Build docs using mdBook or similar static site generator
        const ctr = try ctx.container()
            .from("rust:slim")
            .withExec(&.{ "cargo", "install", "mdbook" })
            .withDirectory("/src", source)
            .withWorkdir("/src")
            // Initialize mdBook if not exists, then build
            .withExec(&.{ "sh", "-c", "if [ ! -f docs/book.toml ]; then mdbook init docs --title 'dagger-zig Documentation'; fi" })
            .withExec(&.{ "mdbook", "build", "docs", "--dest-dir", "_site" });

        return ctr.directory("/src/_site");
    }

    /// Phase 0: Schema Conformance - Validate SDK against Dagger API spec
    pub fn schemaConformance(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        _ = source;
        const validator = SchemaValidator{};

        // Run schema validation
        const schema_report = try validator.validate(ctx);

        // Run conformance tests for core types
        const conformance_core = try validator.conformance(ctx, "core_types");

        // Run conformance tests for container API
        const conformance_container = try validator.conformance(ctx, "container_api");

        // Aggregate reports
        var reports = try ctx.directory();
        reports = try reports.withFile("schema-validation.md", schema_report);
        reports = try reports.withFile("conformance-core.md", conformance_core);
        reports = try reports.withFile("conformance-container.md", conformance_container);

        return reports;
    }

    /// Run conformance tests for a specific category
    pub fn conformance(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        category: []const u8,
    ) !dagger.File {
        _ = self;
        _ = source;
        const validator = SchemaValidator{};
        return try validator.conformance(ctx, category);
    }

    pub fn runTests(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        const runner = try ctx.pipeline("functional-verification-tests")
            .container()
            .from("alpine:latest")
            .withExec(&.{ "apk", "add", "--no-cache", "zig" })
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "zig", "build", "test" });

        const output = try runner.stdout();
        return try ctx.directory().withNewFile("test-output.txt", output);
    }

    pub fn securityScan(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        const scan_ctx = try ctx.pipeline("security-analysis-scan");
        const vuln_report = try VulnerabilityScanner.scanRepositorySarif(&VulnerabilityScanner{}, scan_ctx, source);
        const secret_report = try VulnerabilityScanner.scanSecretsSarif(&VulnerabilityScanner{}, scan_ctx, source);

        var reports = try ctx.directory();
        reports = try reports.withFile("vulnerability.sarif", vuln_report);
        reports = try reports.withFile("secrets.sarif", secret_report);

        return reports;
    }

    pub fn slsaBuild(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        target: []const u8,
    ) !dagger.Container {
        _ = self;
        return try HermeticBuilder.build(&HermeticBuilder{}, ctx, source, .{ .target = target });
    }

    pub fn generateAttestations(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        builder_id: []const u8,
    ) !dagger.Directory {
        _ = self;
        const provenance = try ProvenanceGenerator.generate(
            &ProvenanceGenerator{},
            ctx,
            source,
            builder_id,
            "ci/main.zig",
        );
        const sbom_cdx = try SbomGenerator.cyclonedx(&SbomGenerator{}, ctx, source);
        const sbom_spdx = try SbomGenerator.spdx(&SbomGenerator{}, ctx, source);

        var attestations = try ctx.directory();
        attestations = try attestations.withFile("provenance.json", provenance);
        attestations = try attestations.withFile("sbom.cdx.json", sbom_cdx);
        attestations = try attestations.withFile("sbom.spdx.json", sbom_spdx);

        return attestations;
    }

    pub fn signArtifacts(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        artifacts: dagger.Directory,
        private_key: dagger.Secret,
    ) !dagger.Directory {
        _ = self;
        const provenance = try artifacts.file("provenance.json");
        const sbom = try artifacts.file("sbom.cdx.json");

        const prov_sig = try CosignSigner.signBlob(&CosignSigner{}, ctx, provenance, private_key);
        const sbom_sig = try CosignSigner.signBlob(&CosignSigner{}, ctx, sbom, private_key);

        var signed = artifacts;
        signed = try signed.withFile("provenance.json.sig", prov_sig);
        signed = try signed.withFile("sbom.cdx.json.sig", sbom_sig);

        return signed;
    }

    pub fn fullPipeline(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        // Phase 0: Schema Conformance - Validate SDK against Dagger API spec
        const conformance_reports = try self.schemaConformance(ctx, source);

        // Phase 1: Code Quality - Validate formatting
        const lint_output = try self.lint(ctx, source);
        _ = lint_output;

        // Phase 2: Functional Verification - Run test suite
        const test_output = try self.runTests(ctx, source);
        _ = test_output;

        // Phase 3: Security Analysis - Scan for vulnerabilities and secrets
        const security_reports = try self.securityScan(ctx, source);

        // Phase 4: SLSA L3 Build - Hermetic, reproducible compilation
        const builder = try self.slsaBuild(ctx, source, "x86_64-linux-gnu");

        // Phase 5: Container Security - Scan built artifact
        const built_vuln = try VulnerabilityScanner.scanContainerSarif(&VulnerabilityScanner{}, ctx, builder);

        // Phase 6: Supply Chain Attestation - Generate SBOM and provenance
        const attestations = try self.generateAttestations(ctx, source, "dagger-ci");

        // Phase 7: Artifact Collection - Aggregate all outputs
        var all_artifacts = security_reports;
        all_artifacts = try all_artifacts.withDirectory("conformance-reports", conformance_reports);
        all_artifacts = try all_artifacts.withFile("container-vuln.sarif", built_vuln);
        all_artifacts = try all_artifacts.withDirectory("attestations", attestations);

        return all_artifacts;
    }

    pub fn releasePipeline(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        version: []const u8,
        signing_key: dagger.Secret,
    ) !dagger.Directory {
        // Run full CI pipeline first
        var artifacts = try self.fullPipeline(ctx, source);

        // Sign attestations for release integrity
        const attestations = try artifacts.directory("attestations");
        const signed = try self.signArtifacts(ctx, attestations, signing_key);

        // Replace unsigned with signed attestations
        artifacts = try artifacts.withDirectory("attestations", signed);

        // Generate release metadata
        const metadata_container = try ctx
            .container()
            .from("alpine:latest")
            .withNewFile("/metadata.txt", version);
        const metadata = try metadata_container.file("/metadata.txt");
        artifacts = try artifacts.withFile("version.txt", metadata);

        return artifacts;
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, CiPipeline{});
}
