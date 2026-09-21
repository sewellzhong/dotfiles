local function configure(name)
    return function() require("dotfiles.config")[name]() end
end
return {
    { "folke/lazy.nvim", pin = true },
    {
        "nvim-telescope/telescope.nvim", branch = "0.1.x", cmd = "Telescope",
        dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope-file-browser.nvim" },
        config = configure("telescope"),
    },
    {
        "nvim-tree/nvim-tree.lua", dependencies = { "nvim-tree/nvim-web-devicons" },
        cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
        keys = { { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Toggle File Explorer" } },
        opts = {
            view = { width = 30, side = "left" },
            renderer = { highlight_git = true, highlight_opened_files = "all" },
            filters = { dotfiles = false }, git = { enable = true },
        },
    },
    {
        "dikiaap/minimalist", name = "minimalist", lazy = false, priority = 1000,
        config = function() vim.cmd.colorscheme("minimalist") end,
    },
    { "editorconfig/editorconfig-vim", event = "BufReadPre" },
    { "mattn/emmet-vim", ft = { "html", "css", "javascript", "php" } },
    { "sheerun/vim-polyglot", lazy = false },
    { "tpope/vim-fugitive", cmd = { "Git", "Gdiff", "Glog" } },
    {
        "nvim-lualine/lualine.nvim", event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" }, config = configure("lualine"),
    },
    { "williamboman/mason.nvim", cmd = "Mason", opts = {} },
    {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        cmd = { "MasonToolsInstall", "MasonToolsInstallSync", "MasonToolsUpdate", "MasonToolsUpdateSync" },
        dependencies = { "williamboman/mason.nvim" }, config = configure("tools"),
    },
    {
        "neovim/nvim-lspconfig", version = "v1.8.0",
        event = { "BufReadPre", "BufNewFile" }, dependencies = { "williamboman/mason.nvim" },
        config = configure("lsp"),
    },
    { "mfussenegger/nvim-jdtls", ft = "java" },
    { "stevearc/conform.nvim", event = "BufWritePre", config = configure("conform") },
    {
        "mfussenegger/nvim-lint", event = { "BufReadPost", "BufWritePost", "InsertLeave" },
        config = configure("lint"),
    },
    {
        "nvim-treesitter/nvim-treesitter", event = { "BufReadPost", "BufNewFile" },
        build = ":TSUpdateSync", config = configure("treesitter"),
    },
}
