// Runs a Lua script on fengari (Lua 5.3 in JavaScript) from the repository root, for machines
// without a native Lua. The script sees its arguments in the global `arg` table and can return an
// exit code. fengari has no io.open/io.popen, so the global `read_file(path)` returns a file's
// content.
// Usage: node tools/lua/run.js <script.lua> [args...]
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const [script, ...args] = process.argv.slice(2);
if (!script) {
	console.error("usage: node tools/lua/run.js <script.lua> [args...]");
	process.exit(2);
}
process.chdir(path.resolve(__dirname, "..", ".."));

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_createtable(L, args.length, 1);
lua.lua_pushstring(L, to_luastring(script));
lua.lua_rawseti(L, -2, 0);
args.forEach((value, i) => {
	lua.lua_pushstring(L, to_luastring(value));
	lua.lua_rawseti(L, -2, i + 1);
});
lua.lua_setglobal(L, to_luastring("arg"));

lua.lua_pushjsfunction(L, (state) => {
	const file = lauxlib.luaL_checkstring(state, 1);
	lua.lua_pushstring(state, to_luastring(fs.readFileSync(to_jsstring(file), "utf8")));
	return 1;
});
lua.lua_setglobal(L, to_luastring("read_file"));

if (lauxlib.luaL_loadfile(L, to_luastring(script)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
	console.error(lua.lua_tojsstring(L, -1));
	process.exit(1);
}
process.exit(lua.lua_isinteger(L, -1) ? lua.lua_tointeger(L, -1) : 0);
