import { Composition, staticFile } from "remotion";
import { CodeScene } from "./components/CodeScene";
import { IntroScene } from "./components/IntroScene";
import { OutroScene } from "./components/OutroScene";

// First Pipeline Tutorial - 5 minutes
export const FirstPipeline: React.FC = () => {
  return (
    <>
      {/* Scene 1: Intro (0:00 - 0:15) */}
      <Composition
        id="intro"
        component={IntroScene}
        durationInFrames={15 * 30} // 15 seconds at 30fps
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          title: "Your First Dagger Pipeline in Zig",
          subtitle: "Build containers programmatically",
        }}
      />

      {/* Scene 2: Setup (0:15 - 1:00) */}
      <Composition
        id="setup"
        component={CodeScene}
        durationInFrames={45 * 30}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          title: "1. Project Setup",
          code: `// build.zig.zon excerpt; retain zig init fingerprint and paths.
// Run zig fetch --save=dagger_sdk with this URL to record its hash.
.{
    .name = .my_pipeline,
    .version = "0.1.0", // Your package version, not the SDK version.
    .dependencies = .{
        .dagger_sdk = .{
            .url = "https://github.com/MChorfa/dagger-zig/archive/refs/tags/v0.4.0.tar.gz",
            .hash = "dagger_sdk-0.3.5-LXrZ7GawGACw8A-ST4QbS4wFrBflzYwGM22R1ZcMSKVQ",
        },
    },
}`,
          highlightLines: [8, 9, 10],
          voiceover: "Initialize your project with zig init. Use zig fetch with the release URL to record the dependency hash. Your package version is independent of the SDK version. See Getting Started for the build.zig wiring.",
        }}
      />

      {/* Scene 3: Main Code (1:00 - 3:00) */}
      <Composition
        id="main-code"
        component={CodeScene}
        durationInFrames={120 * 30}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          title: "2. Write the Pipeline",
          code: `const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Connect to Dagger
    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    // Build a container
    const ctr = try client.dag().container(null);
    const alpine = try ctr.from("alpine:latest", null);
    const exec = try alpine.withExec(&.{ "echo", "Hello from Zig!" }, null, null, null, null, null, null, null, null, null, null);
    const output = try exec.stdout();
    defer gpa.free(output);

    std.debug.print("{s}\\n", .{output});
}`,
          highlightLines: [9, 13, 14, 15, 16, 17],
          voiceover: "The key steps: connect to Dagger, build a container from an image, run a command, and get the output.",
        }}
      />

      {/* Scene 4: Run (3:00 - 4:00) */}
      <Composition
        id="run"
        component={CodeScene}
        durationInFrames={60 * 30}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          title: "3. Run the Pipeline",
          code: `# Run under dagger session
dagger run -- zig build run

# Output:
# Hello from Zig!`,
          highlightLines: [1, 2],
          voiceover: "Execute your pipeline using dagger run. This handles the session lifecycle automatically.",
        }}
      />

      {/* Scene 5: Outro (4:00 - 5:00) */}
      <Composition
        id="outro"
        component={OutroScene}
        durationInFrames={60 * 30}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          title: "Next Steps",
          links: [
            { text: "Documentation", url: "https://github.com/MChorfa/dagger-zig" },
            { text: "Examples", url: "https://github.com/MChorfa/dagger-zig/tree/main/examples" },
            { text: "Discord Community", url: "https://discord.gg/dagger" },
          ],
        }}
      />
    </>
  );
};
