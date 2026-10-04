-- Sliders (sliders.lua): the recipe UioSlider around a base slider stretches like the slider does
-- (builtin.css.lua: Slider!horizontal, gravity -1); the value next to a construction slider is a
-- flat button that looks like the base label (construction.css.lua: R::ScriptParamSliderText).
local ssu = require("::/gui/main/stylesheetutil.lua")

---@return table
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	add("R::UioSlider", { gravity = { -1, 0.5 } })
	-- the Line Manager's wait-time sliders have a fixed width next to their value
	add("R::CargoFilterContent R::UioSlider", { gravity = { 0, 0.5 } })

	add("R::ScriptParamSliderAndText Button!uio-slider-value", {
		backgroundColor1 = colorDefault.Invisible,
		borderColor = colorDefault.Invisible,
		padding = { 0, 2, 0, 2 },
		margin = { 0, 0, 0, 0 },
		gravity = { 0, 0.5 },
	})
	add("R::ScriptParamSliderAndText Button!uio-slider-value:hover", { borderColor = colorDefault.AccentLight })
	add("R::ScriptParamSliderAndText Button!uio-slider-value TextView", {
		minSize = { 55, -1 },
		textAlignment = { -1, -1 },
	})
	add("R::ConstructionParamsContent#menu.construction.bottomparams.react R::ScriptParamSliderAndText "
		.. "Button!uio-slider-value TextView", { textAlignment = { 1, -1 } })
	add("DoubleSpinBox!uio-slider-input", { minSize = { 70, -1 }, gravity = { 0, 0.5 } })
	return result
end
