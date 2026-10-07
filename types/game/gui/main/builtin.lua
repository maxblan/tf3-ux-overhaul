---@meta
-- gui/main/builtin.lua, typed after scripts/builtin.d.tl. Params declare the fields this repo passes.
-- All fields are optional: the userdata the engine builds from a param table has defaults for each.

---@class builtin.type.Orientation
---@field Horizontal builtin.type.Orientation
---@field Vertical builtin.type.Orientation

---@class builtin.type.ImageViewScaling
---@field AutoFit builtin.type.ImageViewScaling
---@field AutoZoom builtin.type.ImageViewScaling
---@field Stretch builtin.type.ImageViewScaling

---@class builtin.type.ScrollBarPolicy
---@field AlwaysOff builtin.type.ScrollBarPolicy
---@field AlwaysOn builtin.type.ScrollBarPolicy
---@field AsNeededButAlwaysReserveSpace builtin.type.ScrollBarPolicy
---@field AsNeeded builtin.type.ScrollBarPolicy
---@field Simple builtin.type.ScrollBarPolicy

---@class builtin.type.ListBehavior
---@field Default builtin.type.ListBehavior
---@field AutoDeselectDisabledItems builtin.type.ListBehavior
---@field Navigational builtin.type.ListBehavior

---@class builtin.type.FloatingLayoutOverflowMode
---@field None builtin.type.FloatingLayoutOverflowMode
---@field Overflow builtin.type.FloatingLayoutOverflowMode ignores outerSpacing, borderWidth, padding; may leave the parent
---@field KeepInside builtin.type.FloatingLayoutOverflowMode

---A line shown by builtin.LineViewer (showLines).
---@class builtin.type.LineVisualization
---@field new fun(): builtin.type.LineVisualization
---@field entity Engine.Entity
---@field transparency number

---The `builtin.type` table.
---@class builtin.type
---@field Orientation builtin.type.Orientation
---@field ImageViewScaling builtin.type.ImageViewScaling
---@field ScrollBarPolicy builtin.type.ScrollBarPolicy
---@field ListBehavior builtin.type.ListBehavior
---@field FloatingLayoutOverflowMode builtin.type.FloatingLayoutOverflowMode
---@field LineVisualization builtin.type.LineVisualization

---@class builtin.ComponentParam: react.Param
---@field layout? react.TreeNodeId
---@field name? string
---@field mouseTransparent? boolean

---@class builtin.BoxLayoutParam: react.Param
---@field id? string
---@field children? react.TreeNodeId[]
---@field child? react.TreeNodeId shortcut for children = { child }
---@field orientation? builtin.type.Orientation

---@class builtin.FloatingLayoutParam: react.Param
---@field id? string
---@field children? react.TreeNodeId[]

---Layout child: does not take `meta`. `item` must not be nil.
---@class builtin.FloatingLayoutChildParam
---@field h? number
---@field v? number
---@field overflowMode? builtin.type.FloatingLayoutOverflowMode
---@field localKey? string
---@field item? react.TreeNodeId

---@class builtin.TableLayoutParam: react.Param
---@field id? string
---@field columnWeights? number[]
---@field rows? react.TreeNodeId[] builtin.Row nodes

---@class builtin.RowParam: react.Param
---@field cells? react.TreeNodeId[]

---@class builtin.ScrollAreaParam: react.Param
---@field content? react.TreeNodeId
---@field horizontalPolicy? builtin.type.ScrollBarPolicy
---@field verticalPolicy? builtin.type.ScrollBarPolicy

---@class builtin.ListParam: react.Param
---@field orientation? builtin.type.Orientation
---@field behavior? builtin.type.ListBehavior
---@field deselectAllowed? boolean
---@field onHover? fun(index: integer)
---@field onSelect? fun(index: integer)
---@field onActivate? fun(index: integer)
---@field horizontalScrollBarPolicy? builtin.type.ScrollBarPolicy
---@field verticalScrollBarPolicy? builtin.type.ScrollBarPolicy
---@field children? react.TreeNodeId[]
---@field selectionIndex? integer

---@class builtin.TextViewParam: react.Param
---@field text? string
---@field tooltipWhenClipped? string

---@class builtin.TextInputFieldParam: react.Param
---@field value? string
---@field placeholderText? string shown while the field is empty
---@field onTyping? fun(value: string) on every change while typing
---@field onValueChange? fun(value: string)
---@field onCancel? fun()
---@field onEditingModeChange? fun(editing: boolean)
---@field acceptOnFocusLoss? boolean
---@field focusOnStartEditing? boolean
---@field maxLength? integer

---@class builtin.ImageViewParam: react.Param
---@field path? string
---@field scaling? builtin.type.ImageViewScaling

---@class builtin.KeybindingHintDisplayParam: react.Param
---@field inputAction? string
---@field source? react.RefWrap
---@field sourceId? string

---@class builtin.ProgressBarParam: react.Param
---@field value? number in [0, 1]
---@field thresholds? number[] in [0, 1]
---@field label? string
---@field applyGradient? boolean defaults to true

---@class builtin.ButtonParam: react.Param
---@field content? react.TreeNodeId
---@field onClick? fun()

---`value` (with onValueChange) for a toggle bound to a state, `initialValue` otherwise. 0 or 1.
---@class builtin.ToggleButtonParam: react.Param
---@field content? react.TreeNodeId
---@field onValueChange? fun(value: integer)
---@field initialValue? integer
---@field value? integer

---@class builtin.ToggleButtonGroupChildParam: react.Param
---@field content? react.TreeNodeId

---@alias builtin.ToggleButtonGroupLayout "Horizontal"|"Vertical"|"Flow"|"Uniform"

---@class builtin.ToggleButtonGroupParam: react.Param
---@field buttons? builtin.ToggleButtonGroupChildParam[]
---@field onValueChange? fun(index: integer, value: integer)
---@field deselectAllowed? boolean
---@field layout? builtin.ToggleButtonGroupLayout
---@field initialSelected? integer -1 for none (needs deselectAllowed)
---@field selected? integer

---@class builtin.DoubleSpinBoxApi
---@field startEditing fun(onStop: fun())

---@class builtin.DoubleSpinBoxParam: react.Param
---@field min? number nil: unbounded
---@field max? number nil: unbounded
---@field step? number
---@field value? number
---@field onValueChange? fun(value: number)
---@field startInEditMode? boolean
---@field onStopEditMode? fun()

---@class builtin.SliderParam: react.Param
---@field min? integer
---@field max? integer
---@field step? integer
---@field pageStep? integer
---@field horizontal? boolean
---@field disableGamepadNavigation? boolean
---@field withTicks? boolean
---@field initialValue? integer
---@field value? integer
---@field onValueChange? fun(newValue: integer)

---@class builtin.ComboBoxParam: react.Param
---@field value? integer|number|string
---@field items? react.TreeNodeId[] builtin.ComboBoxItem nodes
---@field onValueChange? fun(newValue: integer|number|string)
---@field compact? boolean

---@class builtin.ComboBoxItemParam: react.Param
---@field value? integer|number|string
---@field content? react.TreeNodeId
---@field available? boolean

---What a DataTable passes to the recipe of each cell.
---@class builtin.TableCellParam
---@field rowKey integer
---@field colKey integer
---@field userParam any the table's userParam, whatever the table's owner passed

---@class builtin.ColumnDescParam: react.Param
---@field name? string
---@field tooltip? string
---@field path? string
---@field headerStyleClass? string
---@field weight? number
---@field recipe? react.Recipe<builtin.TableCellParam>
---@field getCompareValue? fun(rowKey: integer): any sort key of the row: number, string or a table of them
---@field forceLexicographicalStringComparison? boolean

---@class builtin.DataTableApi
---@field scrollToRowKey fun(rowKey: integer, forceTopAlign: boolean)

---@class builtin.DataTableParam: react.Param
---@field columns? react.TreeNodeId[] builtin.ColumnDesc nodes
---@field rowKeys? integer[]
---@field preferredInitialSelectionRowKey? integer
---@field userParam? any passed to newly created cells as TableCellParam.userParam
---@field initialSortColumn? [integer, boolean] 1-based column, true for ascending
---@field onSortColumnChange? fun(columnIndex: integer, ascending: boolean)

---`content` must not be nil.
---@class builtin.WindowParam: react.Param
---@field title? string
---@field onClose? fun()
---@field closable? boolean
---@field pinnable? boolean
---@field content? react.TreeNodeId
---@field id? string
---@field tool? string
---@field compact? boolean
---@field header? react.TreeNodeId
---@field titleEditable? boolean
---@field onTitleChange? fun(title: string)
---@field emptyNameAllowed? boolean defaults to true

---Reusing a window does not change its visibility; moving changes only the z order.
---@class builtin.WindowAPI
local WindowAPI = {}

---@generic T
---@param recipe react.Recipe<T>
---@param params? T
function WindowAPI.addSingletonWindow(recipe, params) end

---@generic T
---@param recipe react.Recipe<T>
---@param key string
---@param params T
function WindowAPI.addWindow(recipe, key, params) end

---@param recipe function
function WindowAPI.moveSingletonWindowToFront(recipe) end

---@param recipe function
---@param key string
function WindowAPI.moveWindowToFront(recipe, key) end

---@param recipe function
function WindowAPI.removeAllWindows(recipe) end

---@param recipe function
---@param key string
function WindowAPI.removeWindow(recipe, key) end

---Api of builtin.RendererComponent (builtin.lua; react.d.tl lists only bind/unbind).
---@class builtin.RenderComponentAPI
---@field bindAction fun(ref: react.RefWrap, actionFn: (fun(): react.TreeNodeId), key2?: string)
---@field unbindAction fun(ref: react.RefWrap)
---@field setActiveOwner fun(ownerRef: react.RefWrap?)
---@field setActiveOwnerOverride fun(ownerRef: react.RefWrap|false|nil) false: no override

---What a tool's push/pop/shelve handlers get from the tool stack.
---@class builtin.ToolStackContext
---@field setActionFn fun(actionFn?: (fun(): react.TreeNodeId), key2?: string)
---@field popSelf fun()
---@field setVariantOverride fun(variant: string)

---A tool of the tool stack (ReactToolDefinition). Params are whatever the tool's pusher passes.
---@class builtin.ToolDefinition
---@field name string
---@field push? fun(ctx: builtin.ToolStackContext, params: any)
---@field pop? fun(ctx: builtin.ToolStackContext, params: any)
---@field shelve? fun(ctx: builtin.ToolStackContext, params: any, shelve: boolean)
---@field getActiveVariant? fun(ctx: builtin.ToolStackContext, params: any): string
---@field getDebugString? fun(ctx: builtin.ToolStackContext, params: any): string

---@class builtin.ToolStackAPI
---@field push fun(toolDef: builtin.ToolDefinition, key: string, params?: any, allowStacking?: boolean)
---@field pop fun(toolDef: builtin.ToolDefinition, key: string)
---@field clear fun()
---@field setActionsDisabled fun(block: boolean)
---@field getActiveTool fun(): (builtin.ToolDefinition?, string?)

---@class builtin.ToolStackParam: react.Param
---@field rendererComponent react.RefWrapApi<builtin.RenderComponentAPI>
---@field defaultTool? builtin.ToolDefinition
---@field defaultToolParam? any params of the default tool, as for ToolStackAPI.push
---@field defaultToolKey? string
---@field showDebugVisualization? boolean

---@alias builtin.TerrainCirclePolicy "FocusSelection"|"Always"|"IfNoEntity"|"Never"

---@class builtin.ActionDescriptorParam: react.Param
---@field tool? string
---@field layer? string
---@field terrainCirclePolicy? builtin.TerrainCirclePolicy
---@field highlightedEntities? Engine.Entity[]
---@field crosshair? boolean
---@field onBack? fun()
---@field horizontalPromptList? boolean
---@field children? react.TreeNodeId[]

---Track builder action descriptor (userdata).
---@class builtin.type.ConstructionAction.TrackEdgeBuilder
---@field resName ResName

---Street builder action descriptor (userdata).
---@class builtin.type.ConstructionAction.StreetEdgeBuilder
---@field resName ResName

---Bulldozer action descriptor (userdata).
---@class builtin.type.ConstructionAction.Bulldozer
---@field undergroundMode boolean

---The construction action's params (one of the builders/modifiers is set), the fields this repo uses.
---@class builtin.ConstructionActionParam: react.Param
---@field streetEdgeBuilder? builtin.type.ConstructionAction.StreetEdgeBuilder
---@field trackEdgeBuilder? builtin.type.ConstructionAction.TrackEdgeBuilder
---@field bulldozer? builtin.type.ConstructionAction.Bulldozer
---@field getProposalStringsFn? fun(proposal: Proposal, proposalData: ProposalData): string[]

---builtin.d.tl declares Recipe<LayerConfig>, but the game passes { config = ... }.
---@class builtin.LayerConfigParam: react.Param
---@field config? LayerConfig

---@class game.gui.main.builtin
---@field type builtin.type
---@field Component react.Recipe<builtin.ComponentParam>
---@field BoxLayout react.Recipe<builtin.BoxLayoutParam>
---@field FloatingLayout react.Recipe<builtin.FloatingLayoutParam>
---@field FloatingLayoutChild react.Recipe<builtin.FloatingLayoutChildParam>
---@field TableLayout react.Recipe<builtin.TableLayoutParam>
---@field Row react.Recipe<builtin.RowParam>
---@field ScrollArea react.Recipe<builtin.ScrollAreaParam>
---@field List react.Recipe<builtin.ListParam>
---@field TextView react.Recipe<builtin.TextViewParam>
---@field TextInputField react.Recipe<builtin.TextInputFieldParam>
---@field ImageView react.Recipe<builtin.ImageViewParam>
---@field KeybindingHintDisplay react.Recipe<builtin.KeybindingHintDisplayParam>
---@field ProgressBar react.Recipe<builtin.ProgressBarParam>
---@field Button react.Recipe<builtin.ButtonParam>
---@field ToggleButton react.Recipe<builtin.ToggleButtonParam>
---@field ToggleButtonGroup react.Recipe<builtin.ToggleButtonGroupParam>
---@field DoubleSpinBox react.RecipeWithApi<builtin.DoubleSpinBoxParam, builtin.DoubleSpinBoxApi>
---@field Slider react.Recipe<builtin.SliderParam>
---@field ComboBox react.Recipe<builtin.ComboBoxParam>
---@field ComboBoxItem react.Recipe<builtin.ComboBoxItemParam>
---@field ColumnDesc react.Recipe<builtin.ColumnDescParam>
---@field DataTable react.RecipeWithApi<builtin.DataTableParam, builtin.DataTableApi>
---@field Window react.Recipe<builtin.WindowParam>
---@field ToolStack react.RecipeWithApi<builtin.ToolStackParam, builtin.ToolStackAPI>
---@field ActionDescriptor react.Recipe<builtin.ActionDescriptorParam>
---@field LayerConfig react.Recipe<builtin.LayerConfigParam>
local M = {}

return M
