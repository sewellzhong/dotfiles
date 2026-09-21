local ok, err = xpcall(function()
    if vim.env.DOTFILES_VERIFY == "1" then
        local config = require("lazy.core.config")
        local names = vim.tbl_keys(config.plugins)
        require("lazy").load({ plugins = names })
        assert(#(_G.dotfiles_errors or {}) == 0, table.concat(_G.dotfiles_errors or {}, "\n"))
        for _, name in ipairs(names) do
            assert(config.plugins[name]._.loaded, "Plugin did not load: " .. name)
        end
        require("jdtls")
        assert(vim.fn.exists(":Telescope") == 2, "Telescope command missing")
        assert(vim.fn.exists(":NvimTreeToggle") == 2, "File tree command missing")
        assert(require("conform").format, "Formatter setup missing")
        assert(require("lint").linters_by_ft.sh, "Shell lint setup missing")
    else
        local root = vim.env.DOTFILES_NVIM_CONFIG
        for _, path in ipairs(vim.fn.glob(root .. "/**/*.lua", false, true)) do
            assert(loadfile(path))
        end
        package.path = root .. "/lua/?.lua;" .. package.path
        local lock = vim.json.decode(table.concat(vim.fn.readfile(root .. "/lazy-lock.json"), "\n"))
        local declared = { ["lazy.nvim"] = true }
        local function visit(spec)
            if type(spec) == "string" then spec = { spec } end
            local name = spec.name or spec[1]:match("([^/]+)$")
            declared[name] = true
            assert(lock[name], "Missing lock entry: " .. name)
            assert(lock[name].commit:match("^[a-f0-9]+$") and #lock[name].commit == 40,
                "Invalid lock commit: " .. name)
            for _, dependency in ipairs(spec.dependencies or {}) do visit(dependency) end
        end
        for _, plugin in ipairs(require("dotfiles.plugins")) do visit(plugin) end
        for name in pairs(lock) do assert(declared[name], "Undeclared locked plugin: " .. name) end
    end
end, debug.traceback)
if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") end
vim.cmd("qa")
