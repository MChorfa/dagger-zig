package runtimeutil

import (
	"strings"
	"testing"
)

func TestModuleBuildScriptChecksSourceSubpathBeforeRoot(t *testing.T) {
	script := ModuleBuildScript("/user-module", "ci")

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
}

func TestModuleBuildScriptOmitsDuplicateSourceRootCandidate(t *testing.T) {
	script := ModuleBuildScript("/user-module", ".")

	if strings.Count(script, `"/user-module"`) != 1 {
		t.Fatalf("expected only one root candidate when source subpath is root: %s", script)
	}
}
