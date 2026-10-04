---@meta

---A recipe with its param, the param type erased (from makeRecipeAndParam).
---@class game.gui.main.content_card.RecipeAndParamErased
---@field recipe react.Recipe<any> erased: called with `param`
---@field param any erased: the param of `recipe`

---@class game.gui.main.content_card.ContentCardParam: react.Param
---@field title string
---@field titleOnHoverFocus? fun(isSelected: boolean)
---@field initialCalloutTextPermanent? string
---@field recipeAndParamPermanent? game.gui.main.content_card.RecipeAndParamErased
---@field extraChildrenPermanent? react.TreeNodeId[]
---@field separatorBetweenExtraChildren? boolean
---@field hasPermanentFocusables? boolean
---@field initialCalloutTextCollapsible? string
---@field recipeAndParamCollapsible? game.gui.main.content_card.RecipeAndParamErased
---@field setCollapsibleExpanded? fun(expanded: boolean)
---@field collapsibleExpanded? boolean
---@field gameCtx game.gui.main.game_context.GameContext
---@field showOnRightSide? boolean

---@class game.gui.main.content_card.ContentCardApi
---@field setPermanentCalloutText fun(text: string)
---@field setCollapsibleCalloutText fun(text: string)

---@class game.gui.main.content_card
---@field ContentCard react.RecipeWithApi<game.gui.main.content_card.ContentCardParam, game.gui.main.content_card.ContentCardApi>
local M = {}

---@generic T
---@param recipe react.Recipe<T>
---@param param T
---@return game.gui.main.content_card.RecipeAndParamErased
function M.makeRecipeAndParam(recipe, param) end

---Functions to set and to read whether a card is expanded, kept in `collapsibleCardsState`.
---@param collapsibleCardsState react.State<table<string, boolean>>
---@param onlyOneExpandable boolean
---@return fun(key: string, expandedValue: boolean) setExpanded
---@return fun(key: string): boolean isExpanded
function M.makeContentCardsCollapsibleFunctions(collapsibleCardsState, onlyOneExpandable) end

return M
