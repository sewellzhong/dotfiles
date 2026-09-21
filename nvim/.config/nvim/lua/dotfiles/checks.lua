-- Compatibility checks for the pinned lazy.nvim in unattended operations.
local M = {}
function M.start()
    local util = require('lazy.core.util')
    local try = util.try
    util.try = function(fn, opts)
        opts = type(opts) == 'string' and { msg = opts } or vim.tbl_extend('force', {}, opts or {})
        if not opts.on_error then
            -- lazy normally schedules this notification; capture it before qa can discard it.
            opts.on_error = function(message)
                table.insert(_G.dotfiles_errors, tostring(message))
                util.error(message)
            end
        end
        return try(fn, opts)
    end
end

function M.tasks()
    local task = require('lazy.manage.task')
    local spawn = task.spawn
    task.spawn = function(self, command, opts)
        local ok = spawn(self, command, opts)
        -- In this manager revision, streamed headless output can hide nonzero exits
        -- from has_errors(). Also catch commands that fail without printing anything.
        if not ok then self:error('Command failed in ' .. self.name .. ': ' .. vim.inspect(command)) end
        return ok
    end
end
return M
