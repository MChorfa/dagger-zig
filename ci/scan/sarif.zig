const std = @import("std");
const dagger = @import("dagger_sdk");

pub const SarifReporter = struct {
    pub fn generateSarif(
        ctx: *dagger.module.Context,
        tool_name: []const u8,
        rule_id: []const u8,
        message: []const u8,
        level: []const u8,
    ) !dagger.File {
        const template = "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"{s}\"}},\"results\":[{\"ruleId\":\"{s}\",\"message\":{\"text\":\"{s}\"},\"level\":\"{s}\"}]}]}";

        const content = try std.fmt.allocPrint(ctx.allocator(), template, .{
            tool_name, rule_id, message, level,
        });

        const container = try ctx.dag()
            .container()
            .from("alpine:latest")
            .withNewFile("/report.sarif", content);

        return try container.file("/report.sarif");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, SarifReporter{});
}
