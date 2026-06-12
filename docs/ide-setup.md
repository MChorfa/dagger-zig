# IDE Setup

The repository works best with Zig language tooling and format-on-save.

## Recommended Setup

Use an editor that supports:

- Zig syntax highlighting
- `zls` language server integration
- format on save
- go-to-definition

## VS Code

Recommended extensions:

```json
{
  "recommendations": ["ziglang.vscode-zig", "tiehuis.zig"]
}
```

Suggested settings:

```json
{
  "zig.zls.path": "zls",
  "zig.formattingProvider": "zls",
  "editor.formatOnSave": true,
  "[zig]": {
    "editor.defaultFormatter": "ziglang.vscode-zig",
    "editor.tabSize": 4,
    "editor.insertSpaces": false
  }
}
```

## Other Editors

Any editor that can talk to `zls` should work. Common choices:

- Neovim with `nvim-lspconfig`
- Vim with an LSP client
- Emacs with `lsp-mode` or `eglot`
- JetBrains with a Zig plugin and `zls`

## ZLS

Install `zls` however you prefer and make sure it is on `PATH`.

Typical checks:

```bash
zls --version
which zls
```

## Sanity Check

Open any `.zig` file and verify:

- symbols resolve
- formatting is available
- the editor sees `build.zig`
- save hooks do not rewrite unrelated code

## Related Pages

- [Getting Started](getting-started.md)
- [Build Guide](build.md)
- [Repository Layout](layout.md)
