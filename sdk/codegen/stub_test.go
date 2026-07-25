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

func TestGenerateZigTypesProducesValidStructure(t *testing.T) {
	// Minimal introspection JSON with one object type, one scalar ID,
	// one enum, and one input object.
	jsonStr := `{
		"__schema": {
			"types": [
				{
					"name": "Container",
					"kind": "OBJECT",
					"fields": [
						{"name": "id", "args": [], "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "ID", "ofType": null}}},
						{"name": "from", "args": [{"name": "address", "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "String", "ofType": null}}}], "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "OBJECT", "name": "Container", "ofType": null}}}
					],
					"inputFields": [],
					"enumValues": []
				},
				{"name": "ContainerID", "kind": "SCALAR", "fields": [], "inputFields": [], "enumValues": []},
				{"name": "String", "kind": "SCALAR", "fields": [], "inputFields": [], "enumValues": []},
				{"name": "ID", "kind": "SCALAR", "fields": [], "inputFields": [], "enumValues": []},
				{
					"name": "CacheSharingMode",
					"kind": "ENUM",
					"fields": [],
					"inputFields": [],
					"enumValues": [{"name": "SHARED"}, {"name": "PRIVATE"}, {"name": "LOCKED"}]
				},
				{
					"name": "BuildArg",
					"kind": "INPUT_OBJECT",
					"fields": [],
					"inputFields": [
						{"name": "name", "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "String", "ofType": null}}},
						{"name": "value", "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "String", "ofType": null}}}
					],
					"enumValues": []
				}
			]
		}
	}`

	output, err := GenerateZigTypes([]byte(jsonStr))
	if err != nil {
		t.Fatalf("GenerateZigTypes failed: %v", err)
	}

	for _, want := range []string{
		"pub const Container = struct",
		"pub const ContainerID = struct",
		"pub const CacheSharingMode = enum",
		"pub const BuildArg = struct",
		`pub fn from(self: Container, address: []const u8) !Container`,
		`pub fn id(self: Container) !ContainerID`,
		"var cur = try self.selection.select",
	} {
		if !strings.Contains(output, want) {
			t.Fatalf("generated output missing %q", want)
		}
	}
}
