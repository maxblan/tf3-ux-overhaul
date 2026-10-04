---@meta
-- api.gui, typed after apidef/api/gui.d.tl. Only what this repository uses.

---@class Gui.Mouse.Event.Type
---@field Pressed Gui.Mouse.Event.Type
---@field Released Gui.Mouse.Event.Type
---@field Clicked Gui.Mouse.Event.Type
---@field Moved Gui.Mouse.Event.Type
---@field Wheel Gui.Mouse.Event.Type
---@field DoubleClicked Gui.Mouse.Event.Type

---A mouse event.
---@class Gui.Mouse.Event
---@field Type Gui.Mouse.Event.Type
---@field type Gui.Mouse.Event.Type
---0 = left, 1 = middle, 2 = right.
---@field button integer
---@field x integer
---@field y integer
---@field xrel integer
---@field yrel integer
---Whether a child component already handled the event.
---@field handled boolean

---@class Gui.Mouse
---@field Event Gui.Mouse.Event

---@class Gui.InputAction.InputActionState
---@field Disabled Gui.InputAction.InputActionState
---@field Inactive Gui.InputAction.InputActionState
---@field Enabled Gui.InputAction.InputActionState

---@class Gui.InputAction
---@field modifierOnlyActionIsActive fun(inputActionId: string): boolean

---@class Gui.ById
---@field isVisibleRecursive fun(id: string): boolean
---@field setVisible fun(id: string, visible: boolean)

---@class Gui.Camera
---@field focusEntity fun(entity: Engine.Entity)

---@class Gui.Sound
---@field playRandomSoundEffect fun(paths: FilePath[])

---@class Gui.ByEntity
---@field isLineEmptyOrVisible fun(entity: Engine.Entity): boolean
---@field isVisible fun(entity: Engine.Entity): boolean
---@field isVehicleVisible fun(entity: Engine.Entity): boolean

---@class Gui.Mission
---@field isCutscenePlaying fun(): boolean

---@class Gui.Game
---The GUI save data of the mod, as a Lua table.
---@field getGuiSaveData fun(modId: string): table
---@field setGuiSaveData fun(modId: string, data: table)
---@field isMapEditor fun(): boolean
---@field getDefaultSavegameId fun(): string

---GUI resources ("gui_res", "gui_res_overwrite").
---@class Gui.GenericRep: ResTypeRep<integer, GenericGameRes>

---The style of a GUI component (styleutil.makeStyle).
---@class StyleSheet

---The GUI (`api.gui`).
---@class Gui
---Fires a React event from outside React. param: any, as each event takes its own parameter.
---@field fireReactEvent fun(name: string, param: any)
---@field mouse Gui.Mouse
---@field inputAction Gui.InputAction
---@field byId Gui.ById
---@field camera Gui.Camera
---@field sound Gui.Sound
---@field byEntity Gui.ByEntity
---@field mission Gui.Mission
---@field game Gui.Game
---@field genericRep Gui.GenericRep
