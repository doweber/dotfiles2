-- load defaults i.e lua_lsp
-- (also sets on_init/capabilities for every server via vim.lsp.config("*", ...)
--  and registers the on_attach keymaps through an LspAttach autocmd)
require("nvchad.configs.lspconfig").defaults()

-- server definitions come from nvim-lspconfig's lsp/*.lua (nvim 0.11+ API).
-- per-server overrides go through vim.lsp.config("<name>", { ... }) if needed.
local servers = { "html", "cssls", "gopls", "ts_ls" }

vim.lsp.enable(servers)
