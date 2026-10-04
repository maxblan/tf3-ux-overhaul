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

---The resource repositories (`api.res`).
---@class Res
---@field cargoClassRep CargoClassRep
---@field cargoTypeRep CargoTypeRep
---@field modelRep ModelRep
---@field streetTemplateRep ResTypeRep<integer, StreetTemplate>
