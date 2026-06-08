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
