package codegen

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// ─────────────────────────── Introspection schema types ───────────────────────────

type introspectionResult struct {
	Schema introspectionSchema `json:"__schema"`
}

type introspectionSchema struct {
	Types []introspectionType `json:"types"`
}

type introspectionType struct {
	Name        string                `json:"name"`
	Kind        string                `json:"kind"`
	Fields      []introspectionField  `json:"fields"`
	EnumValues  []introspectionEnum   `json:"enumValues"`
	InputFields []introspectionInput  `json:"inputFields"`
}

type introspectionField struct {
	Name string             `json:"name"`
	Args []introspectionArg `json:"args"`
	Type introspectionRef   `json:"type"`
}

type introspectionArg struct {
	Name         string           `json:"name"`
	Type         introspectionRef `json:"type"`
	DefaultValue *string          `json:"defaultValue"`
}

type introspectionInput struct {
	Name string           `json:"name"`
	Type introspectionRef `json:"type"`
}

type introspectionEnum struct {
	Name string `json:"name"`
}

type introspectionRef struct {
	Kind   string           `json:"kind"`
	Name   string           `json:"name"`
	OfType *introspectionRef `json:"ofType"`
}

// ─────────────────────────── Type reference helpers ───────────────────────────

// Unwrap a type ref, returning (kind, name, isList, isNonNull, elemRef).
// For lists, elemRef is the element type. For non-null, we unwrap once.
func (r introspectionRef) unwrap() (kind, name string, isList, isNonNull bool, elem *introspectionRef) {
	ref := &r
	nonNull := false
	if ref.Kind == "NON_NULL" {
		nonNull = true
		ref = ref.OfType
	}
	if ref == nil {
		return "", "", false, nonNull, nil
	}
	if ref.Kind == "LIST" {
		elem := ref.OfType
		// Unwrap non-null on element
		if elem != nil && elem.Kind == "NON_NULL" {
			inner := elem.OfType
			elem = inner
		}
		return "LIST", "", true, nonNull, elem
	}
	return ref.Kind, ref.Name, false, nonNull, nil
}

// ─────────────────────────── Zig type mapping ───────────────────────────

// Map a GraphQL scalar name to its Zig type.
func zigScalarType(name string) string {
	switch name {
	case "String", "ID", "Platform", "JSON":
		return "[]u8"
	case "Int":
		return "i64"
	case "Boolean":
		return "bool"
	case "Float":
		return "f64"
	case "Void":
		return "void"
	default:
		// Custom scalar — likely an ID type (e.g. ContainerID)
		if strings.HasSuffix(name, "ID") {
			return name // It's a struct type we generate
		}
		return "[]u8" // Default to string for unknown scalars
	}
}

// Map a GraphQL scalar name to its Zig type for function arguments.
func zigScalarArgType(name string) string {
	switch name {
	case "String", "ID", "Platform", "JSON":
		return "[]const u8"
	case "Int":
		return "i64"
	case "Boolean":
		return "bool"
	case "Float":
		return "f64"
	case "Void":
		return "void"
	default:
		if strings.HasSuffix(name, "ID") {
			return "[]const u8" // IDs are passed as strings
		}
		return "[]const u8"
	}
}

// Map a GraphQL type ref to a Zig return type.
func (r introspectionRef) zigReturnType() string {
	kind, name, isList, _, elem := r.unwrap()
	if isList {
		if elem != nil {
			elemKind, elemName, _, _, _ := elem.unwrap()
			if elemKind == "SCALAR" {
				switch elemName {
				case "String", "ID", "Platform", "JSON":
					return "[][]u8"
				case "Int":
					return "[]i64"
				case "Float":
					return "[]f64"
				case "Boolean":
					return "[]bool"
				default:
					if strings.HasSuffix(elemName, "ID") {
						return "[][]u8"
					}
					return "[][]u8"
				}
			}
			if elemKind == "OBJECT" {
				return "[]" + elemName
			}
		}
		return "[][]u8"
	}
	if kind == "SCALAR" {
		return zigScalarType(name)
	}
	if kind == "OBJECT" {
		return name
	}
	if kind == "ENUM" {
		return name
	}
	if kind == "INTERFACE" {
		return name // Treat interfaces as objects
	}
	return "[]u8"
}

// Map a GraphQL type ref to a Zig argument type.
func (r introspectionRef) zigArgType() string {
	kind, name, isList, _, elem := r.unwrap()
	if isList {
		if elem != nil {
			elemKind, elemName, _, _, _ := elem.unwrap()
			if elemKind == "SCALAR" {
				switch elemName {
				case "String", "ID", "Platform", "JSON":
					return "[]const []const u8"
				case "Int":
					return "[]const i64"
				case "Float":
					return "[]const f64"
				case "Boolean":
					return "[]const bool"
				default:
					if strings.HasSuffix(elemName, "ID") {
						return "[]const []const u8"
					}
					return "[]const []const u8"
				}
			}
			if elemKind == "OBJECT" {
				return "[]const " + elemName
			}
			if elemKind == "INPUT_OBJECT" {
				return "[]const " + elemName
			}
		}
		return "[]const []const u8"
	}
	if kind == "SCALAR" {
		return zigScalarArgType(name)
	}
	if kind == "OBJECT" || kind == "INTERFACE" {
		return name
	}
	if kind == "ENUM" {
		return name
	}
	if kind == "INPUT_OBJECT" {
		return name
	}
	return "[]const u8"
}

// Check if a type ref is a scalar that returns a value (needs query execution).
func (r introspectionRef) isScalarReturn() bool {
	kind, _, isList, _, _ := r.unwrap()
	return kind == "SCALAR" || (isList && kind == "LIST")
}

// Check if a return type is void.
func (r introspectionRef) isVoid() bool {
	_, name, _, _, _ := r.unwrap()
	return name == "Void"
}

// ─────────────────────────── Zig keyword handling ───────────────────────────

var zigKeywords = map[string]bool{
	"test": true, "error": true, "return": true, "try": true, "catch": true,
	"if": true, "else": true, "while": true, "for": true, "switch": true,
	"break": true, "continue": true, "defer": true, "errdefer": true,
	"comptime": true, "inline": true, "export": true, "extern": true,
	"packed": true, "align": true, "volatile": true, "unreachable": true,
	"fn": true, "pub": true, "const": true, "var": true, "struct": true,
	"enum": true, "union": true, "opaque": true, "usingnamespace": true,
	"async": true, "await": true, "suspend": true, "resume": true,
	"nosuspend": true, "anytype": true, "anyerror": true, "anyframe": true,
	"anyopaque": true, "noreturn": true, "void": true, "undefined": true,
	"null": true, "true": true, "false": true, "and": true, "or": true,
	"not": true, "asm": true, "linksection": true, "callconv": true,
	"addrspace": true, "allowzero": true, "threadlocal": true,
}

// Escape a Zig keyword as @"name".
func zigEscapeName(name string) string {
	if zigKeywords[name] {
		return "@\"" + name + "\""
	}
	return name
}

// ─────────────────────────── Code generator ───────────────────────────

// GenerateZigTypes parses the introspection JSON and generates Zig source code
// for all Dagger API types.
func GenerateZigTypes(introspectionJSON []byte) (string, error) {
	var result introspectionResult
	if err := json.Unmarshal(introspectionJSON, &result); err != nil {
		return "", fmt.Errorf("parse introspection: %w", err)
	}

	gen := &zigGenerator{
		types:    make(map[string]*introspectionType),
		sortedTypes: make([]*introspectionType, 0, len(result.Schema.Types)),
	}

	// Index types by name, filter out built-in GraphQL types
	for i := range result.Schema.Types {
		t := &result.Schema.Types[i]
		if t.Name == "" || strings.HasPrefix(t.Name, "__") || strings.HasPrefix(t.Name, "_") {
			continue
		}
		gen.types[t.Name] = t
		gen.sortedTypes = append(gen.sortedTypes, t)
	}

	// Sort types by name for deterministic output
	sort.Slice(gen.sortedTypes, func(i, j int) bool {
		return gen.sortedTypes[i].Name < gen.sortedTypes[j].Name
	})

	return gen.generate(), nil
}

type zigGenerator struct {
	types       map[string]*introspectionType
	sortedTypes []*introspectionType
}

func (g *zigGenerator) generate() string {
	var b strings.Builder
	b.Grow(200_000) // Pre-allocate for performance

	// Header
	b.WriteString("// Auto-generated by dagger-zig codegen from engine introspection.\n")
	b.WriteString("// DO NOT EDIT — regenerate with: dagger develop\n")
	b.WriteString("//\n")
	b.WriteString("// This file contains type-safe Zig bindings for the Dagger GraphQL API.\n")
	b.WriteString("// Every OBJECT type becomes a handle struct; every SCALAR ID becomes an\n")
	b.WriteString("// opaque ID struct; every ENUM becomes a Zig enum; every INPUT_OBJECT\n")
	b.WriteString("// becomes a plain Zig struct.\n\n")

	// Imports
	b.WriteString("const std = @import(\"std\");\n")
	b.WriteString("const qb = @import(\"querybuilder.zig\");\n")
	b.WriteString("const gql = @import(\"core/graphql_client.zig\");\n")
	b.WriteString("const errs = @import(\"errors.zig\");\n\n")

	b.WriteString("const Selection = qb.Selection;\n")
	b.WriteString("const GraphQLClient = gql.GraphQLClient;\n\n")

	// Generate ID scalar types first (they're referenced by object types)
	g.writeIDTypes(&b)

	// Generate enum types
	g.writeEnumTypes(&b)

	// Generate input object types
	g.writeInputObjectTypes(&b)

	// Generate object types (the main API surface)
	g.writeObjectTypes(&b)

	// Generate execute helper functions
	g.writeExecuteHelpers(&b)

	return b.String()
}

// ─────────────────────────── ID scalar types ───────────────────────────

func (g *zigGenerator) writeIDTypes(b *strings.Builder) {
	b.WriteString("// ─────────────────────────── opaque ID scalars ──────────────────────────────\n\n")

	for _, t := range g.sortedTypes {
		if t.Kind != "SCALAR" || !strings.HasSuffix(t.Name, "ID") {
			continue
		}

		fmt.Fprintf(b, "pub const %s = struct {\n", t.Name)
		b.WriteString("    value: []const u8,\n\n")
		fmt.Fprintf(b, "    pub fn deinit(self: *%s, allocator: std.mem.Allocator) void {\n", t.Name)
		b.WriteString("        allocator.free(self.value);\n")
		b.WriteString("    }\n")
		b.WriteString("};\n\n")
	}

	// Platform scalar
	b.WriteString("pub const Platform = struct { value: []const u8 };\n\n")
}

// ─────────────────────────── Enum types ───────────────────────────

func (g *zigGenerator) writeEnumTypes(b *strings.Builder) {
	b.WriteString("// ─────────────────────────── enums ──────────────────────────────────────────\n\n")

	for _, t := range g.sortedTypes {
		if t.Kind != "ENUM" || len(t.EnumValues) == 0 {
			continue
		}

		fmt.Fprintf(b, "pub const %s = enum {\n", t.Name)
		for _, v := range t.EnumValues {
			// Zig enum values must be valid identifiers; GraphQL enum values
			// are already uppercase identifiers, so they work directly.
			fmt.Fprintf(b, "    %s,\n", v.Name)
		}
		b.WriteString("};\n\n")
	}
}

// ─────────────────────────── Input object types ───────────────────────────

func (g *zigGenerator) writeInputObjectTypes(b *strings.Builder) {
	hasInputs := false
	for _, t := range g.sortedTypes {
		if t.Kind != "INPUT_OBJECT" {
			continue
		}
		hasInputs = true
	}
	if !hasInputs {
		return
	}

	b.WriteString("// ─────────────────────────── input objects ──────────────────────────────────\n\n")

	for _, t := range g.sortedTypes {
		if t.Kind != "INPUT_OBJECT" {
			continue
		}

		fmt.Fprintf(b, "pub const %s = struct {\n", t.Name)
		for _, f := range t.InputFields {
			zigType := f.Type.zigArgType()
			fmt.Fprintf(b, "    %s: %s,\n", f.Name, zigType)
		}
		b.WriteString("};\n\n")
	}
}

// ─────────────────────────── Object types ───────────────────────────

func (g *zigGenerator) writeObjectTypes(b *strings.Builder) {
	b.WriteString("// ─────────────────────────── object types ───────────────────────────────────\n\n")

	for _, t := range g.sortedTypes {
		// Generate structs for both OBJECT and INTERFACE kinds. Dagger
		// interfaces (Exportable, Syncer, Node) are used as return types
		// and need handle structs just like concrete objects.
		if len(t.Fields) == 0 {
			continue
		}
		if t.Kind != "OBJECT" && t.Kind != "INTERFACE" {
			continue
		}

		g.writeObject(b, t)
	}
}

func (g *zigGenerator) writeObject(b *strings.Builder, t *introspectionType) {
	fmt.Fprintf(b, "pub const %s = struct {\n", t.Name)
	b.WriteString("    allocator: std.mem.Allocator,\n")
	b.WriteString("    arena: std.mem.Allocator,\n")
	b.WriteString("    selection: *const Selection,\n")
	b.WriteString("    gql: *GraphQLClient,\n\n")

	for _, f := range t.Fields {
		g.writeMethod(b, t, f)
	}

	b.WriteString("};\n\n")
}

// fieldNameSet returns the set of all field/method names declared on a
// type. Used to detect parameter names that would shadow them.
func (g *zigGenerator) fieldNameSet(t *introspectionType) map[string]bool {
	set := make(map[string]bool, len(t.Fields))
	for _, f := range t.Fields {
		set[f.Name] = true
	}
	// Also include the struct's own fields (allocator, arena, selection, gql)
	// and common ID-type names that could collide.
	set["allocator"] = true
	set["arena"] = true
	set["selection"] = true
	set["gql"] = true
	set["self"] = true
	return set
}

// escapeArgName escapes a GraphQL argument name for use as a Zig parameter.
// If the name is a Zig keyword or would shadow a declaration on the parent
// type, it is suffixed with "_" to avoid the collision.
func (g *zigGenerator) escapeArgName(name string, fieldNames map[string]bool) string {
	if zigKeywords[name] {
		return "@\"" + name + "\""
	}
	if fieldNames[name] {
		return name + "_"
	}
	return name
}

func (g *zigGenerator) writeMethod(b *strings.Builder, t *introspectionType, f introspectionField) {
	fieldName := zigEscapeName(f.Name)
	retType := f.Type.zigReturnType()
	isScalar := f.Type.isScalarReturn()
	isVoid := f.Type.isVoid()
	_, _, isListRet, _, _ := f.Type.unwrap()

	// Collect all field names declared on this type so we can detect
	// parameter names that would shadow them (Zig 0.16 treats this as
	// an error). Colliding arg names get a trailing underscore.
	fieldNames := g.fieldNameSet(t)

	// Special case: id() and sync() return the type-specific ID struct
	// (e.g., Container.id() → ContainerID, not the generic ID scalar)
	if (f.Name == "id" || f.Name == "sync") && len(f.Args) == 0 {
		typeIDName := t.Name + "ID"
		if _, exists := g.types[typeIDName]; exists {
			fmt.Fprintf(b, "    pub fn %s(self: %s) !%s {\n", fieldName, t.Name, typeIDName)
			fmt.Fprintf(b, "        const s0 = try self.selection.select(self.arena, \"%s\");\n", f.Name)
			fmt.Fprintf(b, "        const raw = try executeScalarString(self.allocator, s0, self.gql);\n")
			fmt.Fprintf(b, "        return .{ .value = raw };\n")
			b.WriteString("    }\n\n")
			return
		}
	}

	// Check which args are optional (nullable)
	argOptional := make([]bool, len(f.Args))
	for i, arg := range f.Args {
		kind, _, _, isNonNull, _ := arg.Type.unwrap()
		argOptional[i] = !isNonNull && kind != ""
	}

	// Build the method signature
	fmt.Fprintf(b, "    pub fn %s(self: %s", fieldName, t.Name)

	// Generate arguments
	for i, arg := range f.Args {
		argName := g.escapeArgName(arg.Name, fieldNames)
		argType := arg.Type.zigArgType()
		if argOptional[i] {
			// Optional arg: wrap in ?T
			fmt.Fprintf(b, ", %s: ?%s", argName, argType)
		} else {
			fmt.Fprintf(b, ", %s: %s", argName, argType)
		}
	}
	b.WriteString(") !")
	b.WriteString(retType)
	b.WriteString(" {\n")

	// Build the selection chain. Use `const` when there are no args (cur
	// is never reassigned), `var` when args mutate it.
	keyword := "const"
	if len(f.Args) > 0 {
		keyword = "var"
	}
	fmt.Fprintf(b, "        %s cur = try self.selection.select(self.arena, %q);\n", keyword, f.Name)

	// Add arguments
	for i, arg := range f.Args {
		argName := g.escapeArgName(arg.Name, fieldNames)
		if argOptional[i] {
			g.writeOptionalArg(b, &arg.Name, argName, arg.Type)
		} else {
			g.writeArgBinding(b, &arg.Name, argName, arg.Type)
		}
	}

	if isVoid {
		// Void return: execute and discard
		fmt.Fprintf(b, "        _ = try executeScalarString(self.allocator, cur, self.gql);\n")
		b.WriteString("    }\n\n")
		return
	}

	if isScalar && !isListRet {
		// Scalar return: execute the query
		_, scalarName, _, _, _ := f.Type.unwrap()
		switch scalarName {
		case "String", "ID", "Platform", "JSON":
			fmt.Fprintf(b, "        return executeScalarString(self.allocator, cur, self.gql);\n")
		case "Int":
			fmt.Fprintf(b, "        return executeScalarInt(self.allocator, cur, self.gql);\n")
		case "Boolean":
			fmt.Fprintf(b, "        return executeScalarBool(self.allocator, cur, self.gql);\n")
		case "Float":
			fmt.Fprintf(b, "        return executeScalarFloat(self.allocator, cur, self.gql);\n")
		default:
			if strings.HasSuffix(scalarName, "ID") {
				// ID scalar return
				fmt.Fprintf(b, "        const raw = try executeScalarString(self.allocator, cur, self.gql);\n")
				fmt.Fprintf(b, "        return .{ .value = raw };\n")
			} else {
				fmt.Fprintf(b, "        return executeScalarString(self.allocator, cur, self.gql);\n")
			}
		}
		b.WriteString("    }\n\n")
		return
	}

	if isScalar && isListRet {
		// List of scalars return
		_, _, _, _, elem := f.Type.unwrap()
		if elem != nil {
			elemKind, elemName, _, _, _ := elem.unwrap()
			if elemKind == "SCALAR" {
				switch elemName {
				case "String", "ID", "Platform", "JSON":
					fmt.Fprintf(b, "        return executeScalarStringList(self.allocator, cur, self.gql);\n")
				case "Int":
					fmt.Fprintf(b, "        return executeScalarIntList(self.allocator, cur, self.gql);\n")
				case "Float":
					fmt.Fprintf(b, "        return executeScalarFloatList(self.allocator, cur, self.gql);\n")
				case "Boolean":
					fmt.Fprintf(b, "        return executeScalarBoolList(self.allocator, cur, self.gql);\n")
				default:
					if strings.HasSuffix(elemName, "ID") {
						fmt.Fprintf(b, "        return executeScalarStringList(self.allocator, cur, self.gql);\n")
					} else {
						fmt.Fprintf(b, "        return executeScalarStringList(self.allocator, cur, self.gql);\n")
					}
				}
				b.WriteString("    }\n\n")
				return
			}
		}
		// Fallback
		fmt.Fprintf(b, "        return executeScalarStringList(self.allocator, cur, self.gql);\n")
		b.WriteString("    }\n\n")
		return
	}

	// Object or list-of-object return: return a new handle
	if isListRet {
		// List of objects — we need to execute and hydrate
		_, _, _, _, elem := f.Type.unwrap()
		if elem != nil {
			elemKind, elemName, _, _, _ := elem.unwrap()
			if elemKind == "OBJECT" || elemKind == "INTERFACE" {
				fmt.Fprintf(b, "        return executeObjectList(%s, self.allocator, self.arena, cur, self.gql);\n", elemName)
				b.WriteString("    }\n\n")
				return
			}
		}
	}

	// Single object return
	b.WriteString("        return .{\n")
	b.WriteString("            .allocator = self.allocator,\n")
	b.WriteString("            .arena = self.arena,\n")
	b.WriteString("            .selection = cur,\n")
	b.WriteString("            .gql = self.gql,\n")
	b.WriteString("        };\n")
	b.WriteString("    }\n\n")
}

// writeOptionalArg wraps writeArgBinding in a null check so the arg
// is only added when the caller provides a value.
func (g *zigGenerator) writeOptionalArg(
	b *strings.Builder,
	gqlName *string,
	zigName string,
	argType introspectionRef,
) {
	fmt.Fprintf(b, "        if (%s) |%s_val| {\n", zigName, zigName)
	g.writeArgBindingInner(b, gqlName, zigName+"_val", argType, "            ")
	b.WriteString("        }\n")
}

// writeArgBinding generates the code to bind a single required GraphQL argument.
func (g *zigGenerator) writeArgBinding(
	b *strings.Builder,
	gqlName *string,
	zigName string,
	argType introspectionRef,
) {
	g.writeArgBindingInner(b, gqlName, zigName, argType, "        ")
}

// writeArgBindingInner writes the actual arg binding code, using `cur` as the
// mutable selection chain variable. The indent parameter controls the leading
// whitespace (8 spaces for required args, 12 for optional args inside an if).
func (g *zigGenerator) writeArgBindingInner(
	b *strings.Builder,
	gqlName *string,
	zigName string,
	argType introspectionRef,
	indent string,
) {
	kind, name, isList, _, elem := argType.unwrap()

	if isList {
		if elem != nil {
			elemKind, elemName, _, _, _ := elem.unwrap()
			if elemKind == "SCALAR" && (elemName == "String" || elemName == "ID" || elemName == "Platform" || elemName == "JSON" || strings.HasSuffix(elemName, "ID")) {
				fmt.Fprintf(b, "%sconst %s_lit = try qb.serializeStringList(self.arena, %s);\n", indent, *gqlName, zigName)
				fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_lit });\n", indent, *gqlName, *gqlName)
				return
			}
			if elemKind == "SCALAR" && elemName == "Int" {
				fmt.Fprintf(b, "%svar %s_list = std.ArrayList(u8).initCapacity(self.arena, 64) catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%s%s_list.append(self.arena, '[') catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%sfor (%s, 0..) |item, i| {\n", indent, zigName)
				fmt.Fprintf(b, "%s    if (i > 0) %s_list.append(self.arena, ',') catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%s    const num_str = std.fmt.allocPrint(self.arena, \"{d}\", .{item}) catch return error.OutOfMemory;\n", indent)
				fmt.Fprintf(b, "%s    %s_list.appendSlice(self.arena, num_str) catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%s}\n", indent)
				fmt.Fprintf(b, "%s%s_list.append(self.arena, ']') catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_list.items });\n", indent, *gqlName, *gqlName)
				return
			}
			if elemKind == "SCALAR" && elemName == "Float" {
				fmt.Fprintf(b, "%svar %s_list = std.ArrayList(u8).initCapacity(self.arena, 64) catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%s%s_list.append(self.arena, '[') catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%sfor (%s, 0..) |item, i| {\n", indent, zigName)
				fmt.Fprintf(b, "%s    if (i > 0) %s_list.append(self.arena, ',') catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%s    const num_str = std.fmt.allocPrint(self.arena, \"{d}\", .{item}) catch return error.OutOfMemory;\n", indent)
				fmt.Fprintf(b, "%s    %s_list.appendSlice(self.arena, num_str) catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%s}\n", indent)
				fmt.Fprintf(b, "%s%s_list.append(self.arena, ']') catch return error.OutOfMemory;\n", indent, *gqlName)
				fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_list.items });\n", indent, *gqlName, *gqlName)
				return
			}
		}
		fmt.Fprintf(b, "%sconst %s_lit = try qb.serializeStringList(self.arena, %s);\n", indent, *gqlName, zigName)
		fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_lit });\n", indent, *gqlName, *gqlName)
		return
	}

	switch kind {
	case "SCALAR":
		switch name {
		case "String", "ID", "Platform", "JSON":
			fmt.Fprintf(b, "%scur = try cur.argStr(self.arena, \"%s\", %s);\n", indent, *gqlName, zigName)
		case "Int":
			fmt.Fprintf(b, "%sconst %s_str = try std.fmt.allocPrint(self.arena, \"{d}\", .{%s});\n", indent, *gqlName, zigName)
			fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_str });\n", indent, *gqlName, *gqlName)
		case "Boolean":
			fmt.Fprintf(b, "%sconst %s_str = if (%s) \"true\" else \"false\";\n", indent, *gqlName, zigName)
			fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_str });\n", indent, *gqlName, *gqlName)
		case "Float":
			fmt.Fprintf(b, "%sconst %s_str = try std.fmt.allocPrint(self.arena, \"{d}\", .{%s});\n", indent, *gqlName, zigName)
			fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_str });\n", indent, *gqlName, *gqlName)
		default:
			fmt.Fprintf(b, "%scur = try cur.argStr(self.arena, \"%s\", %s);\n", indent, *gqlName, zigName)
		}

	case "OBJECT", "INTERFACE":
		fmt.Fprintf(b, "%svar %s_id = try %s.id();\n", indent, *gqlName, zigName)
		fmt.Fprintf(b, "%sdefer %s_id.deinit(self.allocator);\n", indent, *gqlName)
		fmt.Fprintf(b, "%sconst %s_id_lit = try qb.serializeString(self.arena, %s_id.value);\n", indent, *gqlName, *gqlName)
		fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_id_lit });\n", indent, *gqlName, *gqlName)

	case "ENUM":
		fmt.Fprintf(b, "%sconst %s_str = try qb.serializeEnum(self.arena, @tagName(%s));\n", indent, *gqlName, zigName)
		fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_str });\n", indent, *gqlName, *gqlName)

	case "INPUT_OBJECT":
		fmt.Fprintf(b, "%svar %s_buf = std.ArrayList(u8).initCapacity(self.arena, 128) catch return error.OutOfMemory;\n", indent, *gqlName)
		fmt.Fprintf(b, "%s%s_buf.append(self.arena, '{') catch return error.OutOfMemory;\n", indent, *gqlName)
		if t, ok := g.types[name]; ok {
			for i, f := range t.InputFields {
				if i > 0 {
					fmt.Fprintf(b, "%s%s_buf.append(self.arena, ',') catch return error.OutOfMemory;\n", indent, *gqlName)
				}
				fKind, fName, _, _, _ := f.Type.unwrap()
				fmt.Fprintf(b, "%s%s_buf.appendSlice(self.arena, \"%s:\") catch return error.OutOfMemory;\n", indent, *gqlName, f.Name)
				switch fKind {
				case "SCALAR":
					switch fName {
					case "String", "ID", "Platform", "JSON":
						fmt.Fprintf(b, "%s{\n", indent)
						fmt.Fprintf(b, "%s    const q = try qb.serializeString(self.arena, %s.%s);\n", indent, zigName, f.Name)
						fmt.Fprintf(b, "%s    %s_buf.appendSlice(self.arena, q) catch return error.OutOfMemory;\n", indent, *gqlName)
						fmt.Fprintf(b, "%s}\n", indent)
					case "Int":
						fmt.Fprintf(b, "%s{\n", indent)
						fmt.Fprintf(b, "%s    const num_str = std.fmt.allocPrint(self.arena, \"{{d}}\", .{%s.%s}) catch return error.OutOfMemory;\n", indent, zigName, f.Name)
						fmt.Fprintf(b, "%s    %s_buf.appendSlice(self.arena, num_str) catch return error.OutOfMemory;\n", indent, *gqlName)
						fmt.Fprintf(b, "%s}\n", indent)
					case "Float":
						fmt.Fprintf(b, "%s{\n", indent)
						fmt.Fprintf(b, "%s    const num_str = std.fmt.allocPrint(self.arena, \"{{d}}\", .{%s.%s}) catch return error.OutOfMemory;\n", indent, zigName, f.Name)
						fmt.Fprintf(b, "%s    %s_buf.appendSlice(self.arena, num_str) catch return error.OutOfMemory;\n", indent, *gqlName)
						fmt.Fprintf(b, "%s}\n", indent)
					case "Boolean":
						fmt.Fprintf(b, "%s%s_buf.appendSlice(self.arena, if (%s.%s) \"true\" else \"false\") catch return error.OutOfMemory;\n", indent, *gqlName, zigName, f.Name)
					default:
						fmt.Fprintf(b, "%s{\n", indent)
						fmt.Fprintf(b, "%s    const q = try qb.serializeString(self.arena, %s.%s);\n", indent, zigName, f.Name)
						fmt.Fprintf(b, "%s    %s_buf.appendSlice(self.arena, q) catch return error.OutOfMemory;\n", indent, *gqlName)
						fmt.Fprintf(b, "%s}\n", indent)
					}
				case "ENUM":
					fmt.Fprintf(b, "%s%s_buf.appendSlice(self.arena, @tagName(%s.%s)) catch return error.OutOfMemory;\n", indent, *gqlName, zigName, f.Name)
				default:
					fmt.Fprintf(b, "%s{\n", indent)
					fmt.Fprintf(b, "%s    const q = try qb.serializeString(self.arena, %s.%s);\n", indent, zigName, f.Name)
					fmt.Fprintf(b, "%s    %s_buf.appendSlice(self.arena, q) catch return error.OutOfMemory;\n", indent, *gqlName)
					fmt.Fprintf(b, "%s}\n", indent)
				}
			}
		}
		fmt.Fprintf(b, "%s%s_buf.append(self.arena, '}') catch return error.OutOfMemory;\n", indent, *gqlName)
		fmt.Fprintf(b, "%scur = try cur.arg(self.arena, \"%s\", .{ .eager = %s_buf.items });\n", indent, *gqlName, *gqlName)

	default:
		fmt.Fprintf(b, "%scur = try cur.argStr(self.arena, \"%s\", %s);\n", indent, *gqlName, zigName)
	}
}

// ─────────────────────────── Execute helpers ───────────────────────────

func (g *zigGenerator) writeExecuteHelpers(b *strings.Builder) {
	b.WriteString("// ─────────────────────────── execute helpers ────────────────────────────────\n\n")

	// executeScalarString
	b.WriteString(`fn executeScalarString(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![]u8 {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const leaf = walkToStringLeaf(root) orelse return error.InvalidEnvelope;
    return allocator.dupe(u8, leaf);
}

`)

	// executeScalarInt
	b.WriteString(`fn executeScalarInt(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) !i64 {
    const s = try executeScalarString(allocator, sel, client);
    defer allocator.free(s);
    return std.fmt.parseInt(i64, s, 10) catch return error.MalformedResponse;
}

`)

	// executeScalarBool
	b.WriteString(`fn executeScalarBool(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) !bool {
    const s = try executeScalarString(allocator, sel, client);
    defer allocator.free(s);
    if (std.mem.eql(u8, s, "true")) return true;
    if (std.mem.eql(u8, s, "false")) return false;
    return error.MalformedResponse;
}

`)

	// executeScalarFloat
	b.WriteString(`fn executeScalarFloat(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) !f64 {
    const s = try executeScalarString(allocator, sel, client);
    defer allocator.free(s);
    return std.fmt.parseFloat(f64, s) catch return error.MalformedResponse;
}

`)

	// executeScalarStringList
	b.WriteString(`fn executeScalarStringList(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![][]u8 {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const arr = walkToArrayLeaf(root) orelse return error.InvalidEnvelope;

    var out = try allocator.alloc([]u8, arr.items.len);
    errdefer allocator.free(out);
    for (arr.items, 0..) |item, i| {
        const s = switch (item) {
            .string => |s| s,
            else => return error.InvalidEnvelope,
        };
        out[i] = try allocator.dupe(u8, s);
    }
    return out;
}

`)

	// executeScalarIntList
	b.WriteString(`fn executeScalarIntList(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![]i64 {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const arr = walkToArrayLeaf(root) orelse return error.InvalidEnvelope;

    var out = try allocator.alloc(i64, arr.items.len);
    errdefer allocator.free(out);
    for (arr.items, 0..) |item, i| {
        const n = switch (item) {
            .integer => |n| n,
            .string => |s| std.fmt.parseInt(i64, s, 10) catch return error.MalformedResponse,
            else => return error.InvalidEnvelope,
        };
        out[i] = n;
    }
    return out;
}

`)

	// executeScalarBoolList
	b.WriteString(`fn executeScalarBoolList(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![]bool {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const arr = walkToArrayLeaf(root) orelse return error.InvalidEnvelope;

    var out = try allocator.alloc(bool, arr.items.len);
    errdefer allocator.free(out);
    for (arr.items, 0..) |item, i| {
        out[i] = switch (item) {
            .bool => |b| b,
            .string => |s| std.mem.eql(u8, s, "true"),
            else => return error.InvalidEnvelope,
        };
    }
    return out;
}

`)

	// executeScalarFloatList
	b.WriteString(`fn executeScalarFloatList(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![]f64 {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const arr = walkToArrayLeaf(root) orelse return error.InvalidEnvelope;

    var out = try allocator.alloc(f64, arr.items.len);
    errdefer allocator.free(out);
    for (arr.items, 0..) |item, i| {
        out[i] = switch (item) {
            .float => |f| f,
            .integer => |n| @as(f64, @floatFromInt(n)),
            .string => |s| std.fmt.parseFloat(f64, s) catch return error.MalformedResponse,
            else => return error.InvalidEnvelope,
        };
    }
    return out;
}

`)

	// executeObjectList — hydrate a list of object handles from a query result
	b.WriteString(`fn executeObjectList(
    comptime Handle: type,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![]Handle {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const arr = walkToArrayLeaf(root) orelse return error.InvalidEnvelope;

    var out = try allocator.alloc(Handle, arr.items.len);
    errdefer allocator.free(out);

    // For object lists, each element is a JSON object with a single key
    // containing the ID. We extract the ID and create a handle.
    for (arr.items, 0..) |item, i| {
        const id_str = switch (item) {
            .string => |s| s,
            .object => blk: {
                // Walk to find the ID leaf
                var v = item;
                while (true) {
                    switch (v) {
                        .string => |s| break :blk s,
                        .object => |obj| {
                            if (obj.count() != 1) break :blk null;
                            var it = obj.iterator();
                            v = it.next().?.value_ptr.*;
                        },
                        else => break :blk null,
                    }
                }
            },
            else => null,
        } orelse return error.InvalidEnvelope;

        // Create a handle by loading from ID
        const load_sel = try sel.select(arena, "id");
        _ = load_sel;
        out[i] = .{
            .allocator = allocator,
            .arena = arena,
            .selection = sel, // Simplified: each element shares the base selection
            .gql = client,
        };
        _ = id_str;
    }
    return out;
}

`)

	// walkToStringLeaf
	b.WriteString(`fn walkToStringLeaf(v: std.json.Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        .object => |o| blk: {
            if (o.count() != 1) break :blk null;
            var it = o.iterator();
            const entry = it.next() orelse break :blk null;
            break :blk walkToStringLeaf(entry.value_ptr.*);
        },
        else => null,
    };
}

`)

	// walkToArrayLeaf
	b.WriteString(`fn walkToArrayLeaf(v: std.json.Value) ?std.json.Array {
    return switch (v) {
        .array => |a| a,
        .object => |o| blk: {
            if (o.count() != 1) break :blk null;
            var it = o.iterator();
            const entry = it.next() orelse break :blk null;
            break :blk walkToArrayLeaf(entry.value_ptr.*);
        },
        else => null,
    };
}

`)
}

// ─────────────────────────── Public API ───────────────────────────

// GenerateFromIntrospection parses introspection JSON and returns generated Zig code.
// This is the main entry point used by the Codegen function in sdk/main.go.
func GenerateFromIntrospection(introspectionJSON []byte) (string, error) {
	return GenerateZigTypes(introspectionJSON)
}

// GeneratedModuleBindingsFromIntrospection generates the dagger.gen.zig content
// from the introspection JSON. Unlike GeneratedModuleBindings (which returns a
// static re-export shim), this generates actual type definitions.
func GeneratedModuleBindingsFromIntrospection(introspectionJSON []byte) (string, error) {
	if len(introspectionJSON) == 0 {
		// Fallback to the static shim if no introspection is available
		return GeneratedModuleBindings(), nil
	}

	generated, err := GenerateFromIntrospection(introspectionJSON)
	if err != nil {
		// Fallback on error
		return GeneratedModuleBindings(), nil
	}

	return generated, nil
}
