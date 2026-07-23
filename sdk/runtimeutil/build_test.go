package runtimeutil

import (
	"strings"
	"testing"
)

func TestModuleBuildScriptChecksSourceSubpathBeforeRoot(t *testing.T) {
	script := ModuleBuildScript("/user-module", "ci", "/sdk-lib", ".dagger-sdk-lib")

	first := strings.Index(script, `"/user-module/ci"`)
	second := strings.Index(script, `"/user-module"`)
	if first == -1 || second == -1 {
		t.Fatalf("expected both source-subpath and root candidates in script: %s", script)
	}
	if first > second {
		t.Fatalf("expected source subpath candidate before root candidate: %s", script)
	}
	if !strings.Contains(script, `cd "$build_dir"`) {
		t.Fatalf("expected script to change directory before building: %s", script)
	}
	if !strings.Contains(script, `module-runtime`) {
		t.Fatalf("expected script to prefer module-runtime step when available: %s", script)
	}
	if !strings.Contains(script, `zig build -Doptimize=ReleaseSafe --prefix /out`) {
		t.Fatalf("expected script to run zig build: %s", script)
	}
	// The symlink step must reference both the mount path and the link name.
	if !strings.Contains(script, `/sdk-lib`) {
		t.Fatalf("expected script to reference the SDK lib mount path: %s", script)
	}
	if !strings.Contains(script, `.dagger-sdk-lib`) {
		t.Fatalf("expected script to create the .dagger-sdk-lib symlink: %s", script)
	}
	if !strings.Contains(script, `ln -sfn`) {
		t.Fatalf("expected script to create a symlink: %s", script)
	}
}

func TestModuleBuildScriptOmitsDuplicateSourceRootCandidate(t *testing.T) {
	script := ModuleBuildScript("/user-module", ".", "/sdk-lib", ".dagger-sdk-lib")

	if strings.Count(script, `"/user-module"`) != 1 {
		t.Fatalf("expected only one root candidate when source subpath is root: %s", script)
	}
}
