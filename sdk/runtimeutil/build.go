package runtimeutil

import (
	"fmt"
	"path"
	"strings"
)

// ModuleBuildScript generates the shell script that builds the user's
// Dagger module inside the runtime container.
//
// The script:
//  1. Finds the build directory by checking the source subpath first,
//     then the context root, for a build.zig file.
//  2. Symlinks the mounted SDK library (sdkLibMountPath) into the build
//     directory as sdkLibLinkName, so the generated build.zig.zon's
//     `.path = ".dagger-sdk-lib"` resolves correctly regardless of the
//     source subpath.
//  3. Runs `zig build module-runtime` if that step exists, otherwise
//     falls back to plain `zig build`. Output is prefixed to /out so the
//     binary lands at /out/bin/module.
func ModuleBuildScript(rootPath, sourceSubpath, sdkLibMountPath, sdkLibLinkName string) string {
	cleanSubpath := normalizeSubpath(sourceSubpath)
	candidates := []string{}
	if cleanSubpath != "." {
		candidates = append(candidates, path.Join(rootPath, cleanSubpath))
	}
	candidates = append(candidates, rootPath)

	var builder strings.Builder
	builder.WriteString("set -eu\n")
	builder.WriteString("build_dir=\"\"\n")
	builder.WriteString("for candidate in")
	for _, candidate := range candidates {
		builder.WriteString(fmt.Sprintf(" %q", candidate))
	}
	builder.WriteString(`; do
  if [ -f "$candidate/build.zig" ]; then
    build_dir="$candidate"
    break
  fi
done
if [ -z "$build_dir" ]; then
  echo "ERROR: user module must provide build.zig at the module source root or context root" >&2
  exit 1
fi
cd "$build_dir"
# Symlink the mounted SDK library into the build directory so the
# generated build.zig.zon's relative .path = ".dagger-sdk-lib" resolves.
if [ -d `)
	builder.WriteString(fmt.Sprintf("%q", sdkLibMountPath))
	builder.WriteString(` ]; then
  ln -sfn `)
	builder.WriteString(fmt.Sprintf("%q", sdkLibMountPath))
	builder.WriteString(` `)
	builder.WriteString(fmt.Sprintf("%q", sdkLibLinkName))
	builder.WriteString(`
fi
if zig build --list-steps | grep -Eq '^[[:space:]]+module-runtime([[:space:]]|$)'; then
	zig build module-runtime -Doptimize=ReleaseSafe --prefix /out
else
	# Build in ReleaseSafe so we get the safety checks that matter most
	# (null checks, bounds checks) while keeping dispatch fast.
	zig build -Doptimize=ReleaseSafe --prefix /out
fi`)

	return builder.String()
}

func normalizeSubpath(sourceSubpath string) string {
	clean := path.Clean("/" + sourceSubpath)
	trimmed := strings.TrimPrefix(clean, "/")
	if trimmed == "" {
		return "."
	}
	return trimmed
}
