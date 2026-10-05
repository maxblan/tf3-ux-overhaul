---@meta
-- api.res, typed after apidef/api/res.d.tl. Only what this repository uses.

---A resource repository. Ids are only valid within the same repository.
---@class ResTypeRep<K, T>
---Gets the resource of an existing id.
---@field get fun(id: K): T
---The id of the resource name, -1 if there is none.
---@field find fun(resName: string): K

---@class ModelRep: ResTypeRep<integer, Model>

---@class CargoTypeRep: ResTypeRep<CargoTypeId, CargoType>
---@field getPassengerCargoTypeId fun(): CargoTypeId

---@class CargoClassRep: ResTypeRep<integer, CargoClass>
---The id of the cargo class name, -1 if there is none.
---@field getCargoClassId fun(cargoClass: string): CargoClassId

---Generic resources (*.res.lua: react plugins, react-replacement-config ...). Ids are given in the
---order the resources were loaded: the game's own first, then each mod in its activation order
---(observed in game).
---@class GenericRep: ResTypeRep<integer, GenericGameRes>
---Ids of all resources of a type, e.g. "react-replacement-config" or "react-plugin ::LineEowExtensionPoint".
---@field getAllOfType fun(typeName: string, includeInvisible?: boolean): integer[]
---The resource name, e.g. "ui_overhaul_1::/ui_overhaul/gui/entry.res" ("::/..." for the game's own).
---@field getName fun(id: integer): string

---The resource repositories (`api.res`).
---@class Res
---@field genericRep GenericRep
---@field cargoClassRep CargoClassRep
---@field cargoTypeRep CargoTypeRep
---@field modelRep ModelRep
---@field streetTemplateRep ResTypeRep<integer, StreetTemplate>
