local M = {}
function M.run(update)
    -- Explicit dependency operations must not inherit completion filters (e.g. */tmp/*).
    local wildignore = vim.o.wildignore
    vim.o.wildignore = ''
    local ok, err = xpcall(function()
        local path = assert(vim.env.DOTFILES_NVIM_LOCK, 'Temporary lock file required')
        local original = vim.fn.readfile(path)
        local expected = vim.json.decode(table.concat(original, '\n'))
        require('dotfiles.checks').tasks()
        local manage = require('lazy.manage')
        local config = require('lazy.core.config')
        for _, plugin in pairs(config.plugins) do
            if plugin._.installed then
                -- Python preflight already validated identity. Preserve equivalent SSH/HTTPS
                -- origins so lazy's literal URL comparison cannot delete and reclone them.
                local origin = vim.fn.system({ 'git', '-C', plugin.dir, 'config', '--get', 'remote.origin.url' })
                assert(vim.v.shell_error == 0, 'Missing plugin origin: ' .. plugin.name)
                plugin.url = origin:gsub('%s+$', '')
            end
        end
        local function checked(runner)
            runner:wait()
            for _, plugin in pairs(config.plugins) do
                for _, task in ipairs(plugin._.tasks or {}) do
                    assert(not task:has_errors(), 'Plugin operation failed: ' .. plugin.name .. '\n' .. task:output(vim.log.levels.ERROR))
                end
            end
            assert(#(_G.dotfiles_errors or {}) == 0, table.concat(_G.dotfiles_errors or {}, '\n'))
        end
        checked(manage.install({ wait = true, lockfile = true, show = false }))
        -- install rewrites BOTH the file and lazy's cached lock with existing HEADs.
        -- Restore the original snapshot before asking lazy to restore installed plugins.
        assert(vim.fn.writefile(original, path) == 0, 'Cannot restore temporary lock')
        local lock = require('lazy.manage.lock')
        lock.lock = vim.deepcopy(expected)
        lock._loaded = true
        if update then
            assert(config.plugins['lazy.nvim'].pin, 'lazy.nvim must stay pinned')
            checked(manage.update({ wait = true, show = false }))
            expected = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
        else
            checked(manage.restore({ wait = true, show = false }))
        end
        for name, entry in pairs(expected) do
            local plugin = assert(config.plugins[name], 'Undeclared plugin: ' .. name)
            local commit = vim.fn.system({ 'git', '-C', plugin.dir, 'rev-parse', 'HEAD' }):gsub('%s+$', '')
            assert(vim.v.shell_error == 0 and commit == entry.commit, 'Lock restore failed: ' .. name)
        end
    end, debug.traceback)
    vim.o.wildignore = wildignore
    if not ok then vim.api.nvim_err_writeln(err); vim.cmd('cquit 1') end
    vim.cmd('qa')
end
return M
