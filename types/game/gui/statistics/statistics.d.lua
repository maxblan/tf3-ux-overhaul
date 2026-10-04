---@meta
-- Types of gui/statistics/statistics.d.tl (no module of its own here).

---@alias game.gui.statistics.statistics.StatisticsRecipeParams.OnlyVisible
---| "Lines"
---| "Vehicles"
---| "Depots"
---| "Stations"
---| "Industries"
---| "Towns"
---| "Warehouses"

---A carrier filter button of a statistics tab.
---@class game.gui.statistics.statistics.StatisticsRecipeParams.Category
---@field imageFile string
---@field tooltip string
---@field carrier Carrier

---Params of each tab of the statistics window.
---@class game.gui.statistics.statistics.StatisticsRecipeParams: react.Param
---@field searchString string
---@field filterShowOnlyVisible boolean
---@field filterShowCategories table<integer, boolean> active category indices
---@field initialSortColumn [integer, boolean] 1-based column, true for ascending
---@field onSortColumnChange fun(columnIndex: integer, ascending: boolean)
---@field filterIaComp react.RefWrap
---@field deleteLineFeedback fun(message: string, mode: string, dialogData: game.gui.line_vehicle_mgmt.feedback_list_util.FeedbackDialogParam, id: number)
---@field declareFilterOnMount fun(categories: game.gui.statistics.statistics.StatisticsRecipeParams.Category[], onlyVisible: game.gui.statistics.statistics.StatisticsRecipeParams.OnlyVisible)

---Api of the lines tab.
---@class game.gui.statistics.statistics.StatisticsRecipeApi
---@field getVisualizeLines fun(): builtin.type.LineVisualization[]
