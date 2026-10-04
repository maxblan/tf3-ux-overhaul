---@meta
-- gui/main/react.lua, typed after scripts/react.d.tl.

---Node of the render tree, as recipes and builtins return it.
---@class react.TreeNodeId

---What react.ref() returns: passed as a recipe's first argument, it fills the ref with the node.
---@class react.RefFill

---A recipe called with its params, optionally preceded by react.ref(...).
---@alias react.Recipe<T> (fun(params?: T): react.TreeNodeId) | (fun(ref: react.RefFill, params?: T): react.TreeNodeId)

---A recipe that provides an Api to node refs (react.RefWrapApi). Called like react.Recipe<T>.
---@alias react.RecipeWithApi<T, Api> (fun(params?: T): react.TreeNodeId) | (fun(ref: react.RefFill, params?: T): react.TreeNodeId)

---A recipe with two params.
---@alias react.Recipe2<T1, T2> (fun(p1: T1, p2: T2): react.TreeNodeId) | (fun(ref: react.RefFill, p1: T1, p2: T2): react.TreeNodeId)

---What RegisterRecipe returns: a recipe with the params of its function (up to five). A recipe of
---one param can be annotated as react.Recipe<T>.
---@alias react.RecipeN<T1, T2, T3, T4, T5>
---| fun(p1?: T1, p2?: T2, p3?: T3, p4?: T4, p5?: T5): react.TreeNodeId
---| fun(ref: react.RefFill, p1?: T1, p2?: T2, p3?: T3, p4?: T4, p5?: T5): react.TreeNodeId

---A recipe without params.
---@alias react.Recipe0 react.Recipe<nil>

---The `meta` field every builtin and recipe param accepts.
---@class react.Meta
---@field localKey? string
---@field id? string
---@field tag? string
---@field tooltip? string
---@field class? string
---@field forceFocusable? boolean
---@field disableFocusableRecursive? boolean
---@field mouseTransparent? boolean not in react.d.tl, but the game's recipes pass it
---@field enabled? boolean
---@field styleSheet? StyleSheet
---@field discardNodeIdentity? boolean

---Base of recipe and builtin params: every recipe call accepts `meta` (IRecipeParamWithMeta).
---@class react.Param
---@field meta? react.Meta

---Hook state (ReactStateT): old() is the value of the current render, set() renders again.
---@class react.State<T>
local State = {}

---@return T
function State:old() end

---@param value T
function State:set(value) end

---@param fn fun(old: T): T
function State:transform(fn) end

---@return boolean
function State:hasExpired() end

---Hook ref (ReactRefT): a value kept across renders; set() does not render again.
---@class react.Ref<T>
local Ref = {}

---@return T
function Ref:get() end

---@param value T
function Ref:set(value) end

---@param fn fun(old: T): T
function Ref:transform(fn) end

---@return boolean
function Ref:hasExpired() end

---A rendered node (ReactNodeRef), what a node ref holds once the node exists.
---@class react.NodeRef
local NodeRef = {}

function NodeRef:focus() end

---@param position Vec2i
---@return boolean
function NodeRef:containsPosition(position) end

---@param gravityX number
---@param gravityY number
---@return Vec2f
function NodeRef:getPosition(gravityX, gravityY) end

---@return integer
function NodeRef:getIdentity() end

function NodeRef:ensureVisible() end

---A rendered node of a recipe with an Api (ReactNodeRefApiT).
---@class react.NodeRefApi<Api>: react.NodeRef
local NodeRefApi = {}

---@return Api
function NodeRefApi:getApi() end

---Node ref (ReactRefWrap), from useNodeRef() / useSelfRef(); empty until the node is mounted.
---@class react.RefWrap
local RefWrap = {}

---@return react.NodeRef?
function RefWrap:get() end

---@param value react.NodeRef?
function RefWrap:set(value) end

---@return boolean
function RefWrap:hasExpired() end

---Node ref of a recipe with an Api (ReactRefWrapApiT).
---@class react.RefWrapApi<Api>: react.RefWrap
local RefWrapApi = {}

---@return react.NodeRefApi<Api>?
function RefWrapApi:get() end

---Input action handler config (React.IaHandler).
---@class react.IaHandler

---Input action forward config (React.IaForward).
---@class react.IaForward

---What a react-replacement-config's doReplaceFn gets.
---@class react.ReplacementApi
local ReplacementApi = {}

---The replacement must be compatible with the original (params, provided Api).
---@param originalRecipe function
---@param replacement function
function ReplacementApi.ReplaceRecipe(originalRecipe, replacement) end

---@class game.gui.main.react
local M = {}

---@generic T1, T2, T3, T4, T5
---@param name string
---@param fn fun(p1: T1, p2: T2, p3: T3, p4: T4, p5: T5): react.TreeNodeId?
---@return react.RecipeN<T1, T2, T3, T4, T5>
function M.RegisterRecipe(name, fn) end

---@generic T1, T2, T3, T4, T5
---@param name string
---@param wrappedRecipe function the wrapped recipe (any recipe or builtin)
---@param fn fun(p1: T1, p2: T2, p3: T3, p4: T4, p5: T5): react.TreeNodeId?
---@return react.RecipeN<T1, T2, T3, T4, T5>
function M.RegisterWrapperRecipe(name, wrappedRecipe, fn) end

---Calls the original recipe, ignoring replacements. Not for builtins.
---@generic T
---@param possiblyReplaced react.Recipe<T>
---@param params? T
---@return react.TreeNodeId
---With a node ref first (react.lua forwards `...` to the original recipe); params: the recipe's own.
---@overload fun(possiblyReplaced: function, ref: react.RefFill, params?: any): react.TreeNodeId
function M.CallOriginalRecipe(possiblyReplaced, params) end

---@param recipe function
---@return integer
function M.GetRecipeId(recipe) end

---For debugging; names are not necessarily unique.
---@param recipe function
---@return string
function M.GetRecipeName(recipe) end

---@generic T
---@param initialValue T
---@return react.State<T>
function M.useState(initialValue) end

---@generic T
---@param initialValue T
---@return react.Ref<T>
function M.useRef(initialValue) end

---For a recipe with an Api, annotate the local as react.RefWrapApi<Api> to type getApi().
---@param recipe? function the recipe of the node, for documentation only
---@return react.RefWrap
function M.useNodeRef(recipe) end

---@return react.RefWrap
function M.useSelfRef() end

---@param nodeRef react.RefWrap|react.RefWrap[]
---@return react.RefFill
function M.ref(nodeRef) end

---@param fn fun()
function M.onStep(fn) end

---Runs `fn` every `intervalSeconds` (default 0.5), deferred, with the restricted API.
---@param fn fun()
---@param intervalSeconds? number
---@param jitter? boolean
function M.onStepTimer(fn, intervalSeconds, jitter) end

---@param fn fun()
function M.onMount(fn) end

---@param fn fun()
function M.onUnmount(fn) end

---@param name string
---@param fn fun(name: string, param: any) param: whatever the event's fireEvent passed
function M.onEvent(name, fn) end

---@param source react.RefWrap? nil fires from the root
---@param name string
---@param param? any event payload, any value the listeners agree on
function M.fireEvent(source, name, param) end

---@param fn fun(event: Gui.Mouse.Event): boolean
function M.onMouseEvent(fn) end

---@param api table the functions the recipe offers to node refs (react.NodeRefApi)
function M.provideApi(api) end

---Deprecated in the game in favour of ToolStack; returns the self ref for setActiveOwner().
---@param rendererComponentRef react.RefWrapApi<builtin.RenderComponentAPI>
---@param actionFn? fun(): react.TreeNodeId
---@param key2? string
---@return react.RefWrap
function M.useAction(rendererComponentRef, actionFn, key2) end

---@param inputAction string
---@param handler react.IaHandler|react.IaForward
function M.useInputAction(inputAction, handler) end

---@param action fun()
---@param isEnabled? fun(): (boolean|Gui.InputAction.InputActionState)
---@param buttonPromptTextOverride? string
---@param acceptRepeatedPresses? boolean
---@param isActive? boolean
---@return react.IaHandler
function M.iaHandler(action, isEnabled, buttonPromptTextOverride, acceptRepeatedPresses, isActive) end

---Forwards an input action to the node `targetRef` holds, as `targetAction` (default: the same action).
---@param targetRef react.RefWrap
---@param targetAction? string
---@return react.IaForward
function M.iaForward(targetRef, targetAction) end

---@param disableFocusable boolean
function M.setDisableFocusable(disableFocusable) end

---@param transparent boolean
function M.setMouseTransparent(transparent) end

---Builtin use only in the game.
---@param name string
function M.setName(name) end

---@param childNodeRef react.RefWrap
function M.setPreferredFocusChild(childNodeRef) end

---@param ... string
function M.setStyleClasses(...) end

---@return string
function M.getCurrentRecipeName() end

return M
