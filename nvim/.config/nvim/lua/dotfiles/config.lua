local M = {}

function M.lsp()
    local lspconfig = require("lspconfig")
    local lsp_capabilities = vim.lsp.protocol.make_client_capabilities()

    local function lsp_on_attach(_, bufnr)
        local opts = { noremap = true, silent = true, buffer = bufnr }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    end

    local servers = {
        lua_ls = {
            settings = {
                Lua = {
                    diagnostics = {
                        globals = { "vim" },
                    },
                },
            },
        },
        ts_ls = {},
        html = {},
        cssls = {},
        jsonls = {},
        intelephense = {},
    }

    for server, config in pairs(servers) do
        config.capabilities = lsp_capabilities
        config.on_attach = lsp_on_attach
        lspconfig[server].setup(config)
    end
end

function M.conform()
    local conform = require("conform")
    conform.setup({
        formatters_by_ft = {
            javascript = { "prettierd", "prettier", stop_after_first = true },
            javascriptreact = { "prettierd", "prettier", stop_after_first = true },
            typescript = { "prettierd", "prettier", stop_after_first = true },
            typescriptreact = { "prettierd", "prettier", stop_after_first = true },
            css = { "prettierd", "prettier", stop_after_first = true },
            scss = { "prettierd", "prettier", stop_after_first = true },
            html = { "prettierd", "prettier", stop_after_first = true },
            json = { "prettierd", "prettier", stop_after_first = true },
            markdown = { "prettierd", "prettier", stop_after_first = true },
            lua = { "stylua" },
            sh = { "shfmt" },
        },
        format_on_save = vim.env.DOTFILES_VERIFY ~= "1" and {
            timeout_ms = 1000, lsp_format = "fallback",
        } or nil,
        notify_on_error = true,
        notify_no_formatters = false,
    })
end

function M.lint()
    local lint = require("lint")
    lint.linters_by_ft = {
        javascript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescript = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        php = { "php" },
        sh = { "shellcheck" },
    }

    local lint_augroup = vim.api.nvim_create_augroup("DotfilesLint", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
            if vim.env.DOTFILES_VERIFY ~= "1" then lint.try_lint() end
        end,
    })
end

function M.lualine()
    local lualine = require("lualine")
    lualine.setup({
        options = {
            theme = "auto",
            section_separators = "",
            component_separators = "",
            icons_enabled = true,
        },
        sections = {
            lualine_a = { "mode" },
            lualine_b = { "branch", "diff" },
            lualine_c = { "filename" },
            lualine_x = { "encoding", "fileformat", "filetype" },
            lualine_y = { "progress" },
            lualine_z = { "location" },
        },
    })
end

function M.telescope()
    local telescope = require("telescope")
    local fb_actions = require("telescope").extensions.file_browser.actions
    telescope.setup({
        defaults = {
            prompt_prefix = "🔍 ",
            selection_caret = " ",
            path_display = { "smart" },
        },
        extensions = {
            file_browser = {
                theme = "ivy",
                hijack_netrw = true,
                hidden = true,
                mappings = {
                    ["i"] = {
                        ["<C-w>"] = fb_actions.goto_parent_dir,
                    },
                    ["n"] = {
                        ["h"] = fb_actions.goto_parent_dir,
                    },
                },
            },
        },
    })

    pcall(telescope.load_extension, "file_browser")
end

function M.tools()
    require("mason-tool-installer").setup({
        ensure_installed = {
            "prettier", "prettierd", "eslint_d", "stylua", "shfmt", "shellcheck",
            "lua-language-server", "typescript-language-server", "html-lsp",
            "css-lsp", "json-lsp", "intelephense",
        },
        auto_update = false,
        run_on_start = false, -- Explicit :MasonToolsInstall; startup never installs tools.
    })
end

function M.treesitter()
    local group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "bash", "sh", "lua", "vim", "json", "yaml", "markdown", "java" },
        callback = function() pcall(vim.treesitter.start) end,
    })
end

return M
