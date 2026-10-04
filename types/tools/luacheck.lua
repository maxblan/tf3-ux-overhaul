---@meta luacheck
-- The part of luacheck's library API (tools/lua/vendor/luacheck/src/luacheck/init.lua) that
-- tools/lua/lint.lua uses. The vendored sources are outside the workspace.

---@class luacheck.Event
---@field code string warning code, e.g. "113"; codes starting with "0" are errors
---@field line integer
---@field column integer
---@field end_column integer

--- The events of one file, or a fatal error (`fatal` and `msg` set).
---@class luacheck.FileReport
---@field [integer] luacheck.Event
---@field fatal? string
---@field msg? string

--- One file report per source, with the totals.
---@class luacheck.Report
---@field [integer] luacheck.FileReport
---@field warnings integer
---@field errors integer
---@field fatals integer

-- any: luacheck options mix booleans, strings, numbers and lists (see .luacheckrc).
---@alias luacheck.Options table<string, any>

---@class luacheck
local luacheck = {}

--- Checks sources (or `{ fatal, msg }` tables, passed through) with options per source.
---@param srcs string[]
---@param opts? luacheck.Options[]
---@return luacheck.Report
function luacheck.check_strings(srcs, opts) end

---@param issue luacheck.Event
---@return string
function luacheck.get_message(issue) end

return luacheck
