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
---Width and height of a component, as parts of the screen (0..1).
---@field getSize fun(id: string): { x: number, y: number }

---Camera data {center x, center y, distance, angle, pitch} (Vec5f).
---@class Gui.CameraData
---@field x number
---@field y number

---@class Gui.Camera
---@field focusEntity fun(entity: Engine.Entity)
---@field focusPosition fun(position: Vec3f, distance: number)
---@field getCameraData fun(): Gui.CameraData
---Screen pixel of a world position.
---@field world2Screen fun(position: Vec3f): { x: integer, y: integer }
---Width and height of the viewport, in pixels.
---@field getSize fun(): { x: integer, y: integer }

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
