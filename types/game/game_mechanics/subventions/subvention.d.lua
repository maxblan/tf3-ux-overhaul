---@meta
-- Types of game_mechanics/subventions/subvention.d.tl (no module of its own here).

---@alias game.game_mechanics.subventions.subvention.ISubvention.Status "Proposed"|"Active"|"Complete"|"Failed"

---@class game.game_mechanics.subventions.subvention.ISubvention.ISubventionData
---@field name string
---@field expireDurationProposed number -1: the offer does not expire
---@field expireDuration number
---@field effectDuration integer
---@field toDeliver integer
---@field delivered integer

---A subsidy's script state (ISubvention / Subvention<T>).
---@class game.game_mechanics.subventions.subvention.ISubvention
---@field data game.game_mechanics.subventions.subvention.ISubvention.ISubventionData
---@field id string
---@field acceptedTime? number
---@field spawnTime number
---@field completedTime? number
---@field uid number

---@class game.game_mechanics.subventions.subvention.SubventionCardData.Entry
---@field icon string
---@field name string

---@class game.game_mechanics.subventions.subvention.SubventionCardData.Expiration
---@field value number
---@field name string

---@class game.game_mechanics.subventions.subvention.SubventionCardData.Progress
---@field value number
---@field text string

---@class game.game_mechanics.subventions.subvention.SubventionCardData.Data
---@field text string

---What a subsidy card shows (SubventionCardData).
---@class game.game_mechanics.subventions.subvention.SubventionCardData
---@field title game.game_mechanics.subventions.subvention.SubventionCardData.Entry
---@field deadline? game.game_mechanics.subventions.subvention.SubventionCardData.Entry
---@field description? string
---@field expireDuration? game.game_mechanics.subventions.subvention.SubventionCardData.Expiration
---@field progress? game.game_mechanics.subventions.subvention.SubventionCardData.Progress
---@field cargoIcons? string[]
---@field cargoToDeliver? integer
---@field upfront? game.game_mechanics.subventions.subvention.SubventionCardData.Data[]
---@field failure? game.game_mechanics.subventions.subvention.SubventionCardData.Data[]
---@field complete? game.game_mechanics.subventions.subvention.SubventionCardData.Data[]
---@field status game.game_mechanics.subventions.subvention.ISubvention.Status
