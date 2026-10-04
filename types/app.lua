---@meta
-- The application global `app`, typed after apidef/app.d.tl. Only what this repository uses.

---Savegame namespaces.
---@class App.SaveGameNamespace
---@field getSavegame fun(): string

---High level functions of the application, e.g. for savegames.
---@class App
---@field SaveGameNamespace App.SaveGameNamespace
---@field findAllSavegames fun(namespace: string): SaveGameInfo[]
---@field getSavegameInfo fun(saveId: SaveGameId): Async<SaveGameData>
local App = {}

---Starts a new game; default values for what `startGameParams` leaves out.
---@param startGameParams? StartGameParams
function App.startGame(startGameParams) end

---@param saveId SaveGameId
---@param isMapEditor boolean
---@param info? SaveGameData.SaveGameDetails
---@param isTutorialInit? boolean
function App.loadGame(saveId, isMapEditor, info, isTutorialInit) end

---@param name string
---@param callBack fun()
---@param isMapEditor boolean
---@param skipSetName? boolean
function App.saveGame(name, callBack, isMapEditor, skipSetName) end

---@type App
app = nil
