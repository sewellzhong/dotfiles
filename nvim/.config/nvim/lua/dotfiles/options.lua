if vim.fn.has("nvim-0.10.4") == 0 then error("Neovim 0.10.4 or newer is required") end

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

local python = vim.fn.expand("~/.pyenv/shims/python")
if vim.fn.executable(python) == 1 then vim.g.python3_host_prog = python end

local node = vim.fn.expand("~/.local/opt/node-provider/node_modules/.bin/neovim-node-host")
if vim.fn.executable(node) == 1 then vim.g.node_host_prog = node end

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
