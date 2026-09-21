local ok, err = xpcall(function()
    local root = vim.env.DOTFILES_NVIM_CONFIG
    package.path = root .. '/lua/?.lua;' .. package.path
    local specs = { ['lazy.nvim'] = 'https://github.com/folke/lazy.nvim.git' }
    local function visit(spec)
        if type(spec) == 'string' then spec = { spec } end
        local name = spec.name or spec[1]:match('([^/]+)$')
        specs[name] = spec.url or ('https://github.com/' .. spec[1] .. '.git')
        for _, dependency in ipairs(spec.dependencies or {}) do visit(dependency) end
    end
    for _, spec in ipairs(require('dotfiles.plugins')) do visit(spec) end
    vim.fn.writefile({ vim.json.encode(specs) }, vim.env.DOTFILES_NVIM_SPECS)
end, debug.traceback)
if not ok then vim.api.nvim_err_writeln(err); vim.cmd('cquit 1') end
vim.cmd('qa')
