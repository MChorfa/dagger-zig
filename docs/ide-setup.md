# IDE Setup for dagger-zig

Complete guide for configuring your IDE to work with dagger-zig.

## Visual Studio Code

### Extensions

Add to `.vscode/extensions.json`:

```json
{
  "recommendations": ["ziglang.vscode-zig", "tiehuis.zig"]
}
```

### Settings

Create `.vscode/settings.json`:

```json
{
  "zig.zls.path": "${workspaceFolder}/zig-out/bin/zls",
  "zig.formattingProvider": "zls",
  "editor.formatOnSave": true,
  "[zig]": {
    "editor.defaultFormatter": "ziglang.vscode-zig",
    "editor.tabSize": 4,
    "editor.insertSpaces": false
  },
  "files.associations": {
    "*.zig": "zig",
    "build.zig": "zig"
  }
}
```

### ZLS (Zig Language Server)

1. Build ZLS:

```bash
cd /tmp
git clone https://github.com/zigtools/zls
cd zls
zig build -Doptimize=ReleaseSafe
# Copy binary to project or add to PATH
cp zig-out/bin/zls ~/bin/
```

1. Configure ZLS:

```bash
# Creates ~/.config/zls.json
zls --config
```

## Vim / Neovim

### Using zig.vim

Add to `.vimrc` or `init.vim`:

```vim
" Zig syntax highlighting
Plug 'ziglang/zig.vim'

" LSP configuration
Plug 'neoclide/coc.nvim', {'branch': 'release'}

" Configure COC for Zig
let g:coc_global_extensions = ['coc-zig']

" Format on save
autocmd BufWritePre *.zig :call CocAction('format')
```

### Using nvim-lspconfig

Add to Neovim Lua config:

```lua
require('lspconfig').zls.setup({
  cmd = {'zls'},
  filetypes = {'zig'},
  root_dir = require('lspconfig.util').root_pattern('build.zig', '.git'),
  settings = {
    zls = {
      enable_snippets = true,
      enable_ast_check = true,
      enable_autofix = true,
    }
  }
})

-- Format on save
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*.zig',
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})
```

## Emacs

### Using zig-mode

Add to `init.el`:

```elisp
(use-package zig-mode
  :ensure t
  :hook (zig-mode . lsp-deferred)
  :config
  (setq zig-format-on-save t)
  (setq zig-zls-path "~/bin/zls"))

;; LSP configuration
(use-package lsp-mode
  :ensure t
  :commands lsp
  :hook (zig-mode . lsp))
```

## JetBrains (IntelliJ, CLion)

Use the **ZigBrains** plugin:

1. Go to Settings → Plugins → Marketplace
2. Search "ZigBrains" and install
3. Configure: Settings → Languages & Frameworks → Zig
4. Set ZLS path and enable formatting

## Troubleshooting

### ZLS Not Found

```bash
# Check if zls is in PATH
which zls

# If not found, add to shell profile
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
```

### Format On Save Not Working

VS Code: Check "Zig: Formatting Provider" is set to `zls`

Neovim: Run `:LspInfo` and ensure zls is attached

### Import Errors

Ensure `build.zig.zon` is present and `zig build` has been run:

```bash
zig build
# This creates zig-out/ and sets up module paths
```

## Quick Test

Create `test.zig`:

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("IDE setup complete!\n", .{});
}
```

You should see:

- ✅ Syntax highlighting
- ✅ Auto-completion (type `std.` and see suggestions)
- ✅ Go to definition (Ctrl+Click on `debug`)
- ✅ Format on save (add extra spaces, save, they disappear)
