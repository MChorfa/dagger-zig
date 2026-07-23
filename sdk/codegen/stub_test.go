package codegen

import (
	"strings"
	"testing"
)

func TestGeneratedModuleBindingsAvoidsRemovedUsingnamespace(t *testing.T) {
	bindings := GeneratedModuleBindings()

	if strings.Contains(bindings, "usingnamespace") {
		t.Fatalf("generated bindings still use removed Zig syntax: %s", bindings)
	}

	for _, want := range []string{
		`const sdk = @import("dagger_sdk");`,
		"pub const module = sdk.module;",
		"pub const Container = sdk.Container;",
		"pub const connect = sdk.connect;",
	} {
		if !strings.Contains(bindings, want) {
			t.Fatalf("generated bindings missing %q", want)
		}
	}
}

func TestUserModuleBuildZigWiresDependencyAndModuleRuntimeStep(t *testing.T) {
	s := UserModuleBuildZig()

	for _, want := range []string{
		`b.dependency("dagger_sdk"`,
		`dagger_sdk.module("dagger_sdk")`,
		`.name = "module"`,
		`b.step("module-runtime"`,
		`b.getInstallStep().dependOn`,
	} {
		if !strings.Contains(s, want) {
			t.Fatalf("user build.zig missing %q\n%s", want, s)
		}
	}
}

func TestUserModuleBuildZigZonDeclaresPathDependency(t *testing.T) {
	s := UserModuleBuildZigZon()

	for _, want := range []string{
		`.fingerprint = 0x`,
		`.dagger_sdk = .{`,
		`.path = ".dagger-sdk-lib"`,
		`.minimum_zig_version = "0.16.0"`,
	} {
		if !strings.Contains(s, want) {
			t.Fatalf("user build.zig.zon missing %q\n%s", want, s)
		}
	}
}
