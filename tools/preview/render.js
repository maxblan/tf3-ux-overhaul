// Renders an SVG to a PNG of the SVG's size.
// Usage: node tools/preview/render.js <input.svg> <output.png>
const fs = require("fs");
const { Resvg } = require("@resvg/resvg-js");

const [input, output] = process.argv.slice(2);
if (!input || !output) {
	console.error("usage: node tools/preview/render.js <input.svg> <output.png>");
	process.exit(2);
}
const png = new Resvg(fs.readFileSync(input), { font: { loadSystemFonts: false } }).render().asPng();
fs.writeFileSync(output, png);
console.log(`rendered ${output} (${png.length} bytes)`);
