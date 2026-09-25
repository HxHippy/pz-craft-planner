-- Craft Planner: a Track button beside Craft / Build in the vanilla crafting and build windows.
-- The Craft button gives up enough width on its right for ours, and nothing else moves.

require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"
require "Entity/ISUI/BuildRecipe/ISWidgetBuildControl"

CraftPlanner = CraftPlanner or {}

local FONT_H = getTextManager():getFontHeight(UIFont.Small)
local SPACING = 5

local function currentRecipe(widget)
    return widget.logic and widget.logic:getRecipe()
end

local function isTracked(playerObj, recipe)
    if not playerObj or not recipe then return false end
    for _, name in ipairs(CraftPlanner.getState(playerObj).targets) do
        if name == recipe:getName() then return true end
    end
    return false
end

local function onTrackClicked(widget)
    local recipe = currentRecipe(widget)
    if not recipe then return end
    if isTracked(widget.player, recipe) then
        CraftPlanner.untrack(recipe:getName(), widget.player)
    else
        CraftPlanner.track(recipe:getName(), widget.player)
    end
end

local function trackLabel(tracked)
    return getText(tracked and "UI_CraftPlanner_ButtonTracking" or "UI_CraftPlanner_ButtonTrack")
end

local function buttonWidth()
    local tm = getTextManager()
    return math.max(tm:MeasureStringX(UIFont.Small, trackLabel(true)), tm:MeasureStringX(UIFont.Small, trackLabel(false))) + 20
end

local function patch(class)
    local origCreate = class.createChildren
    function class:createChildren()
        origCreate(self)
        local h = self.buttonCraft and self.buttonCraft:getHeight() or (FONT_H + 6)
        self.buttonTrack = ISButton:new(0, 0, buttonWidth(), h, trackLabel(false), self, onTrackClicked)
        self.buttonTrack.font = UIFont.Small
        self.buttonTrack:initialise()
        self.buttonTrack:instantiate()
        self.buttonTrack:setTooltip(getText("UI_CraftPlanner_ButtonTip"))
        self:addChild(self.buttonTrack)
    end

    local origLayout = class.calculateLayout
    function class:calculateLayout(w, h)
        origLayout(self, w, h)
        local craft, track = self.buttonCraft, self.buttonTrack
        if not craft or not track then return end
        local tw = track:getWidth()
        craft:setWidth(math.max(40, craft:getWidth() - tw - SPACING))
        track:setX(craft:getRight() + SPACING)
        track:setY(craft:getY())
        track:setHeight(craft:getHeight())
    end

    local origPrerender = class.prerender
    function class:prerender()
        origPrerender(self)
        if self.buttonTrack then
            local recipe = currentRecipe(self)
            self.buttonTrack.enable = recipe ~= nil
            self.buttonTrack:setTitle(trackLabel(isTracked(self.player, recipe)))
        end
    end
end

patch(ISWidgetHandCraftControl)
patch(ISWidgetBuildControl)
