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
        var signer = try ctx.container();
        signer = try signer.from("gcr.io/projectsigstore/cosign:v2.2.0");
        signer = try signer.withFile("/input", blob);
        signer = try signer.withSecretVariable("COSIGN_PRIVATE_KEY", private_key);
        signer = try signer.withExec(&.{
            "cosign",             "sign-blob",
            "--key",              "env://COSIGN_PRIVATE_KEY",
            "--output-signature", "/output.sig",
            "/input",
        });

        return try signer.file("/output.sig");
    }

    pub fn signContainer(
        ctx: *dagger.module.Context,
        image_ref: []const u8,
        private_key: dagger.Secret,
    ) ![]const u8 {
        const signer = try ctx.dag()
            .container()
            .from("gcr.io/projectsigstore/cosign:v2.2.0")
            .withSecretVariable("COSIGN_PRIVATE_KEY", private_key)
            .withExec(&.{
            "cosign",  "sign",
            "--key",   "env://COSIGN_PRIVATE_KEY",
            image_ref,
        });

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
        var verifier = try ctx.container();
        verifier = try verifier.from("gcr.io/projectsigstore/cosign:v2.2.0");
        verifier = try verifier.withFile("/input", blob);
        verifier = try verifier.withFile("/input.sig", signature);
        verifier = try verifier.withSecretVariable("COSIGN_PUBLIC_KEY", public_key);
        verifier = try verifier.withExec(&.{
            "cosign",      "verify-blob",
            "--key",       "env://COSIGN_PUBLIC_KEY",
            "--signature", "/input.sig",
            "/input",
        });

        const output = try verifier.stdout();
        var dir = try ctx.directory();
        return try dir.withNewFile("verify-output.txt", output);
    }

    pub fn verifyContainer(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        image_ref: []const u8,
        public_key: dagger.Secret,
    ) !dagger.File {
        _ = self;
        var verifier = try ctx.container();
        verifier = try verifier.from("gcr.io/projectsigstore/cosign:v2.2.0");
        verifier = try verifier.withSecretVariable("COSIGN_PUBLIC_KEY", public_key);
        verifier = try verifier.withExec(&.{
            "cosign",  "verify",
            "--key",   "env://COSIGN_PUBLIC_KEY",
            image_ref,
        });

        const output = try verifier.stdout();
        var dir = try ctx.directory();
        return try dir.withNewFile("container-verify.txt", output);
    }

    pub fn generateKeyPair(
        self: *const CosignSigner,
        ctx: *dagger.Context,
    ) !dagger.Directory {
        _ = self;
        var generator = try ctx.container();
        generator = try generator.from("gcr.io/projectsigstore/cosign:v2.2.0");
        generator = try generator.withExec(&.{
            "cosign",              "generate-key-pair",
            "--output-key-prefix", "cosign",
        });

        return try generator.directory("/");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, CosignSigner{});
}
