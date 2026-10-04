// Renders a gallery card (SVG) to a PNG of the SVG's size, with the given fonts and with image hrefs
// resolved against a resources directory (the in-game screenshots).
// Usage: node tools/gallery/render.js <input.svg> <output.png> <resources dir> <font file>...
const fs = require("fs");
const path = require("path");
const { Resvg } = require(path.join(__dirname, "..", "preview", "node_modules", "@resvg", "resvg-js"));

const [input, output, resourcesDir, ...fontFiles] = process.argv.slice(2);
if (!input || !output || !resourcesDir || fontFiles.length === 0) {
	console.error("usage: node tools/gallery/render.js <input.svg> <output.png> <resources dir> <font file>...");
	process.exit(2);
}
// resvg-js loads no local files: each screenshot href is inlined as a data URI (read once per file)
const inlined = new Map();
const svg = fs.readFileSync(input, "utf8").replace(/href="([^"#:]+\.png)"/g, (_m, href) => {
	if (!inlined.has(href)) {
		inlined.set(href, fs.readFileSync(path.join(resourcesDir, href)).toString("base64"));
	}
	return `href="data:image/png;base64,${inlined.get(href)}"`;
});
const resvg = new Resvg(svg, {
	font: { loadSystemFonts: false, fontFiles, defaultFontFamily: "Lato" },
	imageRendering: 0, // optimizeQuality: smooth scaling of the screenshots
});
const png = resvg.render().asPng();
fs.writeFileSync(output, png);
console.log(`rendered ${output} (${png.length} bytes)`);
