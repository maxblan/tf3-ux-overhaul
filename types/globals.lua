---@meta
-- Globals the game defines for every script (apidef/main.d.tl, base/base/mod.lua, base/base/init.lua),
-- the global `data` of resource files, and the test runner's read_file.

-- Declared as typed variables, not functions, so that specs can replace them (_G._ = ...).

---Translates `id` (the mod's strings.json and the game's catalogs).
---@type fun(id: string): string
_ = nil

---Translates `id` in a context, e.g. pGetText("noun", "Load"); context nil = none, as `_` does.
---@type fun(context: string?, id: string): string
pGetText = nil

---Translates with plural handling. Does not see a mod's strings.json.
---@type fun(singularId: string, pluralId: string, n: integer): string
nGetText = nil

---Prints to the game log (stdout.txt); any values, printed with tostring.
---@type fun(...: any)
debugPrint = nil

---Resource files (.res.lua, .script.lua, .css.lua, ...) define it; the engine calls it to read the
---resource table, whose shape depends on the resource type. Nil until a resource file defines it.
---@type (fun(): table)?
data = nil

---pairs() in key order, for tables with sortable keys (base/base/init.lua). Mods may wrap it.
---@generic K, V
---@param t table<K, V>
---@return fun(t: table<K, V>, k?: K): K, V
---@return table<K, V>
---@return nil
function orderedPairs(t) end

---The React registry (base/base/init.lua).
---@class _react
---Replacement recipe per recipe id (react.GetRecipeId).
---@field recipeReplace table<integer, function>
---Recipe id per builtin name ("Window" ...).
---@field builtin table<string, integer>
---Per wrapper recipe (react.RegisterWrapperRecipe): the id of the recipe it wraps.
---@field recipeMetas table<integer, { innerRecipeId: integer }?>
_react = {}

---Reads a whole file (tools/lua/run.js, for the tools only).
---@param path string
---@return string
function read_file(path) end
