-- Resolve this file itself so `nvim -u /path/to/repo/.../init.lua` works before Stow.
local source = debug.getinfo(1, "S").source:sub(2)
local config_dir = vim.fn.fnamemodify(vim.fn.resolve(source), ":p:h")
vim.opt.rtp:prepend(config_dir)
package.path = config_dir .. "/lua/?.lua;" .. config_dir .. "/lua/?/init.lua;" .. package.path
vim.g.dotfiles_config_dir = config_dir

if vim.env.DOTFILES_VERIFY == "1" or vim.env.DOTFILES_NVIM_SYNC == "1" then
    _G.dotfiles_errors = {}
    local write_error = vim.api.nvim_err_writeln
    vim.api.nvim_err_writeln = function(message)
        table.insert(_G.dotfiles_errors, tostring(message))
        return write_error(message)
    end
    local notify = vim.notify
    vim.notify = function(message, level, opts)
        if level == vim.log.levels.ERROR then table.insert(_G.dotfiles_errors, tostring(message)) end
        return notify(message, level, opts)
    end
end
local strict = vim.env.DOTFILES_VERIFY == "1" or vim.env.DOTFILES_NVIM_SYNC == "1"
local startup_ok, startup_error = xpcall(function()
    require("dotfiles.options")
    require("dotfiles.keymaps")
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not vim.loop.fs_stat(lazypath) then
        if strict then error("lazy.nvim missing; run ./dotfiles.sh install") end
        vim.notify("lazy.nvim missing; run ./dotfiles.sh install", vim.log.levels.WARN)
        return
    end
    vim.opt.rtp:prepend(lazypath)
    if strict then require("dotfiles.checks").start() end
    local specs = require("dotfiles.plugins")
    if vim.env.DOTFILES_NVIM_SYNC == "1" and vim.env.DOTFILES_VERIFY ~= "1" then
        -- Provision first; eager plugins may not exist yet or may still be at old commits.
        local function defer(spec)
            if type(spec) == "string" then spec = { spec } end
            spec.lazy = true
            for i, dependency in ipairs(spec.dependencies or {}) do spec.dependencies[i] = defer(dependency) end
            return spec
        end
        for i, spec in ipairs(specs) do specs[i] = defer(spec) end
    end
    require("lazy").setup(specs, {
        lockfile = vim.env.DOTFILES_NVIM_LOCK or (config_dir .. "/lazy-lock.json"),
        install = { missing = false },
        checker = { enabled = false },
        change_detection = { enabled = false },
        rocks = { enabled = false },
        pkg = { enabled = false },
    })
end, debug.traceback)
if not startup_ok then
    vim.api.nvim_err_writeln(startup_error)
    if strict then vim.cmd("cquit 1") end
end
