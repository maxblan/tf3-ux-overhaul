// Runs spec/**/*_spec.lua with a Busted-compatible API on fengari (Lua 5.3 in JavaScript), for
// machines without a native Lua. Each spec file gets a fresh Lua state.
// Usage (from anywhere): node tools/lua/run_specs.js [filter]
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const root = path.resolve(__dirname, "..", "..");
const filter = process.argv[2] || "";
process.chdir(root);

function findSpecs(dir) {
	return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) return entry.name === "ingame" ? [] : findSpecs(full);
		return entry.name.endsWith("_spec.lua") && full.includes(filter) ? [full] : [];
	}).sort();
}

function run(L, code) {
	if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
		throw new Error(lua.lua_tojsstring(L, -1));
	}
}

let passed = 0;
let failed = 0;

for (const spec of findSpecs("spec")) {
	const relative = path.relative(root, spec).split(path.sep).join("/");
	console.log(relative);
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);
	try {
		run(L, `BUSTED = dofile("tools/lua/busted.lua"); dofile("spec/support/setup.lua")`);
		run(L, `dofile("${relative}")`);
	} catch (err) {
		console.log(`  FAIL ${relative}: ${err.message}`);
		failed++;
		continue;
	}
	lua.lua_getglobal(L, to_luastring("BUSTED"));
	lua.lua_getfield(L, -1, to_luastring("passed"));
	lua.lua_getfield(L, -2, to_luastring("failed"));
	passed += lua.lua_tointeger(L, -2);
	failed += lua.lua_tointeger(L, -1);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
