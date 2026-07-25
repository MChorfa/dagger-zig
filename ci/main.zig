const std = @import("std");
const dagger = @import("dagger_sdk");

const HermeticBuilder = @import("build/hermetic.zig").HermeticBuilder;
const ProvenanceGenerator = @import("attest/provenance.zig").ProvenanceGenerator;
const SbomGenerator = @import("attest/sbom.zig").SbomGenerator;
const VulnerabilityScanner = @import("scan/vulnerability.zig").VulnerabilityScanner;
const CosignSigner = @import("sign/cosign.zig").CosignSigner;
const SchemaValidator = @import("dagger_schema").SchemaValidator;
const MarkdownLinter = @import("markdown.zig").MarkdownLinter;

pub const CiPipeline = struct {
    pub fn lint(
        self: *const CiPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        const pipeline_ctx = try ctx.pipeline("code-quality-lint");
        var runner = try pipeline_ctx.container();
        runner = try runner.from("alpine:latest", null);
        runner = try runner.withExec(&.{ "apk", "add", "--no-cache", "zig" }, null, null, null, null, null, null, null, null, null, null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);
        runner = try runner.withExec(&.{ "zig", "fmt", "--check", "src/" }, null, null, null, null, null, null, null, null, null, null);

        const output = try runner.stdout();
        var dir = try ctx.directory();
        dir = try dir.withNewFile("lint-output.txt", output, null);
        return try dir.file("lint-output.txt");
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

        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        // Build docs using mdBook or similar static site generator
        var ctr = try ctx.container();
        ctr = try ctr.from("rust:slim", null);
        ctr = try ctr.withExec(&.{ "cargo", "install", "mdbook" }, null, null, null, null, null, null, null, null, null, null);
        ctr = try ctr.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        ctr = try ctr.withWorkdir("/src", null);
        ctr = try ctr.withExec(&.{ "sh", "-c", "if [ ! -f docs/book.toml ]; then mdbook init docs --title 'dagger-zig Documentation'; fi" }, null, null, null, null, null, null, null, null, null, null);
        ctr = try ctr.withExec(&.{ "mdbook", "build", "docs", "--dest-dir", "_site" }, null, null, null, null, null, null, null, null, null, null);

        return ctr.directory("/src/_site", null);
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
        var schema_report_id = try schema_report.id();
        defer schema_report_id.deinit(ctx.allocator());
        reports = try reports.withFile("schema-validation.md", schema_report_id.value, null, null);
        var conformance_core_id = try conformance_core.id();
        defer conformance_core_id.deinit(ctx.allocator());
        reports = try reports.withFile("conformance-core.md", conformance_core_id.value, null, null);
        var conformance_container_id = try conformance_container.id();
        defer conformance_container_id.deinit(ctx.allocator());
        reports = try reports.withFile("conformance-container.md", conformance_container_id.value, null, null);

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
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        const pipeline_ctx = try ctx.pipeline("functional-verification-tests");
        var runner = try pipeline_ctx.container();
        runner = try runner.from("alpine:latest", null);
        runner = try runner.withExec(&.{ "apk", "add", "--no-cache", "zig" }, null, null, null, null, null, null, null, null, null, null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);
        runner = try runner.withExec(&.{ "zig", "build", "test" }, null, null, null, null, null, null, null, null, null, null);

        const output = try runner.stdout();
        var dir = try ctx.directory();
        dir = try dir.withNewFile("test-output.txt", output, null);
        return try dir.file("test-output.txt");
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
        var vuln_report_id = try vuln_report.id();
        defer vuln_report_id.deinit(ctx.allocator());
        reports = try reports.withFile("vulnerability.sarif", vuln_report_id.value, null, null);
        var secret_report_id = try secret_report.id();
        defer secret_report_id.deinit(ctx.allocator());
        reports = try reports.withFile("secrets.sarif", secret_report_id.value, null, null);

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
            "dagger-zig",
            "0000000000000000000000000000000000000000000000000000000000000000",
        );
        const sbom_cdx = try SbomGenerator.cyclonedx(&SbomGenerator{}, ctx, source);
        const sbom_spdx = try SbomGenerator.spdx(&SbomGenerator{}, ctx, source);

        var attestations = try ctx.directory();
        var provenance_id = try provenance.id();
        defer provenance_id.deinit(ctx.allocator());
        attestations = try attestations.withFile("provenance.json", provenance_id.value, null, null);
        var sbom_cdx_id = try sbom_cdx.id();
        defer sbom_cdx_id.deinit(ctx.allocator());
        attestations = try attestations.withFile("sbom.cdx.json", sbom_cdx_id.value, null, null);
        var sbom_spdx_id = try sbom_spdx.id();
        defer sbom_spdx_id.deinit(ctx.allocator());
        attestations = try attestations.withFile("sbom.spdx.json", sbom_spdx_id.value, null, null);

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
        var prov_sig_id = try prov_sig.id();
        defer prov_sig_id.deinit(ctx.allocator());
        signed = try signed.withFile("provenance.json.sig", prov_sig_id.value, null, null);
        var sbom_sig_id = try sbom_sig.id();
        defer sbom_sig_id.deinit(ctx.allocator());
        signed = try signed.withFile("sbom.cdx.json.sig", sbom_sig_id.value, null, null);

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
        var conformance_id = try conformance_reports.id();
        defer conformance_id.deinit(ctx.allocator());
        all_artifacts = try all_artifacts.withDirectory("conformance-reports", conformance_id.value, null, null, null, null, null);
        var built_vuln_id = try built_vuln.id();
        defer built_vuln_id.deinit(ctx.allocator());
        all_artifacts = try all_artifacts.withFile("container-vuln.sarif", built_vuln_id.value, null, null);
        var attestations_id = try attestations.id();
        defer attestations_id.deinit(ctx.allocator());
        all_artifacts = try all_artifacts.withDirectory("attestations", attestations_id.value, null, null, null, null, null);

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
        var signed_id = try signed.id();
        defer signed_id.deinit(ctx.allocator());
        artifacts = try artifacts.withDirectory("attestations", signed_id.value, null, null, null, null, null);

        // Generate release metadata
        var metadata_ctr = try ctx.container();
        metadata_ctr = try metadata_ctr.from("alpine:latest", null);
        metadata_ctr = try metadata_ctr.withNewFile("/metadata.txt", version, null, null, null);
        const metadata = try metadata_ctr.file("/metadata.txt", null);
        var metadata_id = try metadata.id();
        defer metadata_id.deinit(ctx.allocator());
        artifacts = try artifacts.withFile("version.txt", metadata_id.value, null, null);

        return artifacts;
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, CiPipeline{});
}
