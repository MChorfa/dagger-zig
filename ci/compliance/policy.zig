const std = @import("std");
const dagger = @import("dagger_sdk");

const policy_rego =
    \\package supply_chain.governance
    \\
    \\default allow := false
    \\
    \\allow if {
    \\    has_valid_type
    \\    has_correct_subject
    \\    is_secure_builder
    \\    has_slsa_v1_build_definition
    \\}
    \\
    \\has_valid_type if {
    \\    input._type == "https://in-toto.io/Statement/v1"
    \\    input.predicateType == "https://slsa.dev/provenance/v1"
    \\}
    \\
    \\has_correct_subject if {
    \\    some i
    \\    input.subject[i].name == "sbom.spdx.json"
    \\    count(input.subject[i].digest.sha256) == 64
    \\}
    \\
    \\is_secure_builder if {
    \\    input.predicate.runDetails.builder.id == "https://dagger.io/engine"
    \\}
    \\
    \\has_slsa_v1_build_definition if {
    \\    input.predicate.buildDefinition.buildType == "https://dagger.io/build/v1"
    \\}
;

pub const PolicyGate = struct {
    /// validate runs OPA against the provenance JSON and returns the policy result.
    /// Returns "true" or "false" as file content; callers must check the value to gate promotion.
    pub fn validate(
        self: *const PolicyGate,
        ctx: *dagger.Context,
        provenance: dagger.File,
    ) !dagger.File {
        _ = self;
        var gate = try ctx.container();
        gate = try gate.from("openpolicyagent/opa:latest");
        gate = try gate.withFile("/provenance.json", provenance);
        gate = try gate.withNewFile("/policy.rego", policy_rego);
        gate = try gate.withExec(&.{
            "/opa",                               "eval",
            "--input",                            "/provenance.json",
            "--data",                             "/policy.rego",
            "--format",                           "raw",
            "data.supply_chain.governance.allow",
        });
        const result_raw = try gate.stdout();
        var out = try ctx.container();
        out = try out.from("alpine:latest", null);
        out = try out.withNewFile("/policy-result.txt", result_raw);
        return out.file("/policy-result.txt");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, PolicyGate{});
}
