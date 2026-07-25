const std = @import("std");
const dagger = @import("dagger_sdk");

pub const CosignSigner = struct {
    pub const SignConfig = struct {
        oidc_issuer: []const u8 = "https://gitlab.com",
        oidc_client_id: []const u8 = "sigstore",
    };

    pub fn signBlob(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        blob: dagger.File,
        private_key: dagger.Secret,
    ) !dagger.File {
        _ = self;
        var blob_id = try blob.id();
        defer blob_id.deinit(ctx.allocator());
        var key_id = try private_key.id();
        defer key_id.deinit(ctx.allocator());

        var signer = try ctx.container();
        signer = try signer.from("gcr.io/projectsigstore/cosign:v2.2.0", null);
        signer = try signer.withFile("/input", blob_id.value, null, null, null);
        signer = try signer.withSecretVariable("COSIGN_PRIVATE_KEY", key_id.value);
        signer = try signer.withExec(&.{
            "cosign",             "sign-blob",
            "--key",              "env://COSIGN_PRIVATE_KEY",
            "--output-signature", "/output.sig",
            "/input",
        }, null, null, null, null, null, null, null, null, null, null);

        return try signer.file("/output.sig", null);
    }

    pub fn signContainer(
        ctx: *dagger.module.Context,
        image_ref: []const u8,
        private_key: dagger.Secret,
    ) ![]const u8 {
        var key_id = try private_key.id();
        defer key_id.deinit(ctx.allocator());

        const signer = try ctx.dag()
            .container()
            .from("gcr.io/projectsigstore/cosign:v2.2.0", null)
            .withSecretVariable("COSIGN_PRIVATE_KEY", key_id.value)
            .withExec(&.{
            "cosign",  "sign",
            "--key",   "env://COSIGN_PRIVATE_KEY",
            image_ref,
        }, null, null, null, null, null, null, null, null, null, null);

        return try signer.stdout();
    }

    pub fn verifyBlob(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        blob: dagger.File,
        signature: dagger.File,
        public_key: dagger.Secret,
    ) !dagger.File {
        _ = self;
        var blob_id = try blob.id();
        defer blob_id.deinit(ctx.allocator());
        var sig_id = try signature.id();
        defer sig_id.deinit(ctx.allocator());
        var key_id = try public_key.id();
        defer key_id.deinit(ctx.allocator());

        var verifier = try ctx.container();
        verifier = try verifier.from("gcr.io/projectsigstore/cosign:v2.2.0", null);
        verifier = try verifier.withFile("/input", blob_id.value, null, null, null);
        verifier = try verifier.withFile("/input.sig", sig_id.value, null, null, null);
        verifier = try verifier.withSecretVariable("COSIGN_PUBLIC_KEY", key_id.value);
        verifier = try verifier.withExec(&.{
            "cosign",      "verify-blob",
            "--key",       "env://COSIGN_PUBLIC_KEY",
            "--signature", "/input.sig",
            "/input",
        }, null, null, null, null, null, null, null, null, null, null);

        const output = try verifier.stdout();
        var dir = try ctx.directory();
        dir = try dir.withNewFile("/verify-output.txt", output, null);
        return dir.file("/verify-output.txt");
    }

    pub fn verifyContainer(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        image_ref: []const u8,
        public_key: dagger.Secret,
    ) !dagger.File {
        _ = self;
        var key_id = try public_key.id();
        defer key_id.deinit(ctx.allocator());

        var verifier = try ctx.container();
        verifier = try verifier.from("gcr.io/projectsigstore/cosign:v2.2.0", null);
        verifier = try verifier.withSecretVariable("COSIGN_PUBLIC_KEY", key_id.value);
        verifier = try verifier.withExec(&.{
            "cosign",  "verify",
            "--key",   "env://COSIGN_PUBLIC_KEY",
            image_ref,
        }, null, null, null, null, null, null, null, null, null, null);

        const output = try verifier.stdout();
        var dir = try ctx.directory();
        dir = try dir.withNewFile("/container-verify.txt", output, null);
        return dir.file("/container-verify.txt");
    }

    pub fn signAttestation(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        predicate: dagger.File,
        subject: dagger.File,
        oidc_token: dagger.Secret,
    ) !dagger.File {
        _ = self;
        var predicate_id = try predicate.id();
        defer predicate_id.deinit(ctx.allocator());
        var subject_id = try subject.id();
        defer subject_id.deinit(ctx.allocator());
        var token_id = try oidc_token.id();
        defer token_id.deinit(ctx.allocator());

        var signer = try ctx.container();
        signer = try signer.from("ghcr.io/sigstore/cosign/cosign:v2.2.3", null);
        signer = try signer.withFile("/predicate.json", predicate_id.value, null, null, null);
        signer = try signer.withFile("/subject", subject_id.value, null, null, null);
        signer = try signer.withSecretVariable("SIGSTORE_ID_TOKEN", token_id.value);
        signer = try signer.withExec(&.{
            "cosign",          "attest",
            "--yes",           "--predicate",
            "/predicate.json", "--type",
            "slsaprovenance1", "--output-bundle",
            "/output.bundle",  "/subject",
        }, null, null, null, null, null, null, null, null, null, null);
        return signer.file("/output.bundle", null);
    }

    pub fn generateKeyPair(
        self: *const CosignSigner,
        ctx: *dagger.Context,
    ) !dagger.Directory {
        _ = self;
        var generator = try ctx.container();
        generator = try generator.from("gcr.io/projectsigstore/cosign:v2.2.0", null);
        generator = try generator.withExec(&.{
            "cosign",              "generate-key-pair",
            "--output-key-prefix", "cosign",
        }, null, null, null, null, null, null, null, null, null, null);

        return try generator.directory("/", null);
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, CosignSigner{});
}
