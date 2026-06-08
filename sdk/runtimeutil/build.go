package runtimeutil

import (
	"fmt"
	"path"
	"strings"
)

func ModuleBuildScript(rootPath string, sourceSubpath string) string {
	cleanSubpath := normalizeSubpath(sourceSubpath)
	candidates := []string{}
	if cleanSubpath != "." {
		candidates = append(candidates, path.Join(rootPath, cleanSubpath))
	}
	candidates = append(candidates, rootPath)

	var builder strings.Builder
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
