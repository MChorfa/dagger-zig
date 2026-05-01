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
          code: `// build.zig.zon
.{
    .name = .my_pipeline,
    .version = "0.1.0",
    .dependencies = .{
        .dagger_sdk = .{
            .url = "git+https://github.com/MChorfa/dagger-zig#v0.2.0",
        },
    },
}`,
          highlightLines: [6, 7, 8, 9],
          voiceover: "First, add dagger-zig as a dependency in your build.zig.zon file.",
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

pub fn main() !void {
    // Initialize allocator and I/O
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var io_impl: std.Io.Threaded = .init(gpa.allocator());
    defer io_impl.deinit();

    // Connect to Dagger
    var client = try dagger.connect(gpa.allocator(), io_impl.io(), .{});
    defer client.close();

    // Build a container
    const output = try client.dag()
        .container()
        .from("alpine:latest")
        .withExec(&.{"echo", "Hello from Zig!"})
        .stdout();

    std.debug.print("{s}\\n", .{output});
}`,
          highlightLines: [12, 13, 14, 15, 16, 17],
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
