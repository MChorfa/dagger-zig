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
        const signer = try ctx
            .container()
            .from("gcr.io/projectsigstore/cosign:v2.2.0")
            .withFile("/input", blob)
            .withSecretVariable("COSIGN_PRIVATE_KEY", private_key)
            .withExec(&.{
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
        const verifier = try ctx
            .container()
            .from("gcr.io/projectsigstore/cosign:v2.2.0")
            .withFile("/input", blob)
            .withFile("/input.sig", signature)
            .withSecretVariable("COSIGN_PUBLIC_KEY", public_key)
            .withExec(&.{
            "cosign",      "verify-blob",
            "--key",       "env://COSIGN_PUBLIC_KEY",
            "--signature", "/input.sig",
            "/input",
        });

        const output = try verifier.stdout();
        return try ctx.directory().withNewFile("verify-output.txt", output);
    }

    pub fn verifyContainer(
        self: *const CosignSigner,
        ctx: *dagger.Context,
        image_ref: []const u8,
        public_key: dagger.Secret,
    ) !dagger.File {
        _ = self;
        const verifier = try ctx
            .container()
            .from("gcr.io/projectsigstore/cosign:v2.2.0")
            .withSecretVariable("COSIGN_PUBLIC_KEY", public_key)
            .withExec(&.{
            "cosign",  "verify",
            "--key",   "env://COSIGN_PUBLIC_KEY",
            image_ref,
        });

        const output = try verifier.stdout();
        return try ctx.directory().withNewFile("container-verify.txt", output);
    }

    pub fn generateKeyPair(
        self: *const CosignSigner,
        ctx: *dagger.Context,
    ) !dagger.Directory {
        _ = self;
        const generator = try ctx
            .container()
            .from("gcr.io/projectsigstore/cosign:v2.2.0")
            .withExec(&.{
            "cosign",              "generate-key-pair",
            "--output-key-prefix", "cosign",
        });

        return try generator.directory("/");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, CosignSigner{});
}
