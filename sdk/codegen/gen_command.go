//go:build ignore

// Command gen generates sdk/lib/src/gen.zig from the Dagger engine's
// introspection JSON. Run with:
//
//	go run sdk/codegen/gen_command.go <introspection.json> <output.zig>
//
// If no introspection file is provided, it reads from stdin.
package main

import (
	"fmt"
	"io"
	"os"

	"dagger/dagger-zig-sdk/codegen"
)

func main() {
	var input io.Reader
	var output string

	switch len(os.Args) {
	case 3:
		f, err := os.Open(os.Args[1])
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: open %s: %v\n", os.Args[1], err)
			os.Exit(1)
		}
		defer f.Close()
		input = f
		output = os.Args[2]
	case 2:
		input = os.Stdin
		output = os.Args[1]
	default:
		fmt.Fprintf(os.Stderr, "usage: %s [introspection.json] output.zig\n", os.Args[0])
		os.Exit(1)
	}

	data, err := io.ReadAll(input)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: read input: %v\n", err)
		os.Exit(1)
	}

	generated, err := codegen.GenerateFromIntrospection(data)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: generate: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile(output, []byte(generated), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "error: write %s: %v\n", output, err)
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "generated %s (%d bytes)\n", output, len(generated))
}
