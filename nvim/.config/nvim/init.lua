-- ========================
-- Neovim init.lua
-- ========================

local o = vim.o
local wo = vim.wo
local opt = vim.opt

-- ========================
-- Providers
-- ========================
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.g.python3_host_prog = vim.fn.expand("~/.pyenv/shims/python")

vim.g.node_host_prog = vim.fn.expand("~/.local/opt/node-provider/node_modules/.bin/neovim-node-host")

-- ========================
-- General Settings
-- ========================
o.compatible = false
wo.number = true
wo.cursorline = true
o.expandtab = true
o.autoindent = true
o.autoread = true
o.backspace = "indent,eol,start"
o.foldenable = true
o.foldmethod = "syntax"
o.foldlevel = 0
o.foldnestmax = 5
opt.formatoptions = "croq2nl1"
o.hidden = true
o.history = 500
o.hlsearch = true
o.ignorecase = true
o.incsearch = true
o.lazyredraw = true
o.mouse = "a"
o.errorbells = false
o.showmode = false
o.wrap = false
o.scrolloff = 3
o.shiftwidth = 4
o.softtabstop = 4
opt.shortmess:append("I")
o.smartcase = true
o.splitbelow = true
o.splitright = true
o.undofile = true
o.ruler = true
o.wildmenu = true
o.wildmode = "list:longest"
opt.termguicolors = true
o.encoding = "utf-8"
-- o.fileencoding = "utf-8"
-- opt.fileencodings = "utf-8"

-- Lisp words
opt.lispwords:append({
    "defroutes",
    "defpartial",
    "defpage",
    "defaction",
    "deffilter",
    "defview",
    "defsection",
    "describe",
    "it",
})

-- Wildignore
opt.wildignore:append({
    ".DS_Store",
    "*.jpg",
    "*.jpeg",
    "*.gif",
    "*.png",
    "*.psd",
    "*.o",
    "*.obj",
    "*.min.js",
    "*/node_modules/*",
    "*/vendor/*",
    "*/.git/*",
    "*/.hg/*",
    "*/.svn/*",
    "*/.sass-cache/*",
    "*/log/*",
    "*/tmp/*",
    "*/build/*",
    "*/dist/*",
})

-- Directories
local data_path = vim.fn.stdpath("data")
opt.backupdir = data_path .. "/backup"
opt.directory = data_path .. "/swap"
opt.undodir = data_path .. "/undo"

-- ========================
-- Plugin Management (lazy.nvim)
-- ========================
local lazypath = data_path .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.notify("lazy.nvim not found. Run ./dotfiles.sh install to install Neovim plugins.", vim.log.levels.WARN)
    return
end
vim.opt.rtp:prepend(lazypath)

local install_missing_plugins = vim.env.DOTFILES_NVIM_SYNC == "1"
local dotfiles_verify = vim.env.DOTFILES_VERIFY == "1"

require("lazy").setup({
    -- Telescope + File Browser
    {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = { "nvim-lua/plenary.nvim" },
        cmd = "Telescope",
    },
    {
        "nvim-telescope/telescope-file-browser.nvim",
    },

    -- nvim-tree (Side directory tree)
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
        keys = {
            { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Toggle File Explorer" },
        },
        config = function()
            local nvim_tree_ok, nvim_tree = pcall(require, "nvim-tree")
            if nvim_tree_ok then
                nvim_tree.setup({
                    view = {
                        width = 30,
                        side = "left",
                    },
                    renderer = {
                        highlight_git = true,
                        highlight_opened_files = "all",
                    },
                    filters = {
                        dotfiles = false,
                    },
                    git = {
                        enable = true,
                    },
                })
            else
                vim.notify("nvim-tree.lua not found. Run :Lazy sync.", vim.log.levels.WARN)
            end
        end,
    },

    -- Colorscheme
    {
        "dikiaap/minimalist",
        name = "minimalist",
        lazy = false,
        priority = 1000,
    },

    -- EditorConfig
    {
        "editorconfig/editorconfig-vim",
        event = "BufReadPre",
    },

    -- Emmet
    {
        "mattn/emmet-vim",
        ft = { "html", "css", "javascript", "php" },
    },

    -- Polyglot
    {
        "sheerun/vim-polyglot",
        lazy = false,
    },

    -- Fugitive
    {
        "tpope/vim-fugitive",
        cmd = { "Git", "Gdiff", "Glog" },
    },

    -- Lualine (statusline)
    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
    },

    -- External tooling, formatters, linters, and LSP
    {
        "williamboman/mason.nvim",
        cmd = "Mason",
    },
    {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        dependencies = { "williamboman/mason.nvim" },
    },
    {
        "neovim/nvim-lspconfig",
        version = "v1.8.0",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = { "williamboman/mason.nvim" },
    },
    {
     "mfussenegger/nvim-jdtls",
     ft = { "java" },
    },
    {
        "stevearc/conform.nvim",
        event = { "BufWritePre" },
    },
    {
        "mfussenegger/nvim-lint",
        event = { "BufReadPost", "BufWritePost", "InsertLeave" },
    },

    -- nvim-treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        event = { "BufReadPost", "BufNewFile" },
        build = ":TSUpdate",
        config = function()
            local treesitter_group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true })

            vim.api.nvim_create_autocmd("FileType", {
                group = treesitter_group,
                pattern = {
                    "bash",
                    "sh",
                    "lua",
                    "vim",
                    "json",
                    "yaml",
                    "markdown",
                    "java",
                },
                callback = function()
                    pcall(vim.treesitter.start)
                end,
            })
        end,
    },
}, {
    install = {
        missing = install_missing_plugins,
    },
})

-- ========================
-- Colorscheme
-- ========================
local ok, _ = pcall(vim.cmd, "colorscheme minimalist")
if not ok then
    vim.notify("colorscheme 'minimalist' not found!", vim.log.levels.WARN)
end

-- ========================
-- Mason setup
-- ========================
local mason_ok, mason = pcall(require, "mason")
if mason_ok and not dotfiles_verify then
    mason.setup()
else
    if not dotfiles_verify then
        vim.notify("mason.nvim not found. Run :Lazy sync.", vim.log.levels.WARN)
    end
end

local tool_installer_ok, tool_installer = pcall(require, "mason-tool-installer")
if tool_installer_ok and not dotfiles_verify then
    tool_installer.setup({
        ensure_installed = {
            "prettier",
            "prettierd",
            "eslint_d",
            "stylua",
            "shfmt",
            "shellcheck",
            "lua-language-server",
            "typescript-language-server",
            "html-lsp",
            "css-lsp",
            "json-lsp",
            "intelephense",
        },
        auto_update = false,
        run_on_start = true,
    })
end

-- ========================
-- LSP setup
-- ========================
local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
if lspconfig_ok and not dotfiles_verify then
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
elseif not dotfiles_verify then
    vim.notify("nvim-lspconfig not found. Run :Lazy sync.", vim.log.levels.WARN)
end

-- ========================
-- Formatting setup
-- ========================
local conform_ok, conform = pcall(require, "conform")
if conform_ok and not dotfiles_verify then
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
        format_on_save = {
            timeout_ms = 1000,
            lsp_format = "fallback",
        },
        notify_on_error = true,
        notify_no_formatters = false,
    })
elseif not dotfiles_verify then
    vim.notify("conform.nvim not found. Run :Lazy sync.", vim.log.levels.WARN)
end

-- ========================
-- Lint setup
-- ========================
local lint_ok, lint = pcall(require, "lint")
if lint_ok and not dotfiles_verify then
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
            lint.try_lint()
        end,
    })
elseif not dotfiles_verify then
    vim.notify("nvim-lint not found. Run :Lazy sync.", vim.log.levels.WARN)
end

vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { noremap = true, silent = true })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { noremap = true, silent = true })

-- ========================
-- Lualine (statusline)
-- ========================
local lualine_ok, lualine = pcall(require, "lualine")
if lualine_ok then
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
else
    vim.notify("lualine.nvim not found. Run :Lazy sync.", vim.log.levels.WARN)
end

-- ========================
-- Telescope setup
-- ========================
local telescope_ok, telescope = pcall(require, "telescope")
local fb_ok, fb_actions = pcall(function()
    return require("telescope").extensions.file_browser.actions
end)

if telescope_ok and fb_ok then
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
else
    vim.notify("telescope.nvim or telescope-file-browser.nvim not found. Run :Lazy sync.", vim.log.levels.WARN)
end

-- ========================
-- Keymaps
-- ========================
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>fe", "<cmd>Telescope file_browser<cr>", { noremap = true, silent = true })
