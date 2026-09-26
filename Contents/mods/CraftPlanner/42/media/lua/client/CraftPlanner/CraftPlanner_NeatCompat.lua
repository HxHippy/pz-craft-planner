-- Craft Planner: Track button for Neat Crafting, which replaces the vanilla crafting window.
-- The icon sits in the top-right corner of the recipe icon, mirroring Neat's favourite star.
-- Patched at OnGameBoot so load order doesn't matter, and it does nothing without Neat Crafting.

require "CraftPlanner/CraftPlanner_Buttons"

CraftPlanner = CraftPlanner or {}

local TRACK_ICON = "media/ui/CraftPlanner/Icon_Track.png"
local COLOR_TRACKED = { r = 0.3, g = 0.9, b = 0.4, a = 1 }
local COLOR_IDLE = { r = 1, g = 1, b = 1, a = 0.6 }

local function onTrackClicked(panel)
    CraftPlanner.toggleTracked(panel.player, panel.logic and panel.logic:getRecipe())
end

local function patchNeat()
    local P = NC_RecipeInfoPanel
    if not P or P.cpPatched then return end
    P.cpPatched = true

    local origCreate = P.createChildren
    function P:createChildren()
        origCreate(self)
        local btn = ISButton:new(0, 0, 10, 10, "", self, onTrackClicked)
        btn.displayBackground = false
        btn.image = getTexture(TRACK_ICON)
        btn.textureColor = COLOR_IDLE
        btn:initialise()
        btn:instantiate()
        btn:setTooltip(getText("UI_CraftPlanner_ButtonTip"))
        self:addChild(btn)
        self.cpTrackButton = btn
    end

    local origRelayout = P.relayoutFavouriteButton
    function P:relayoutFavouriteButton()
        origRelayout(self)
        local btn = self.cpTrackButton
        if not btn then return end
        local size = self.height / 4
        btn:setX(self.height - size - self.padding)
        btn:setY(self.padding)
        btn:setWidth(size)
        btn:setHeight(size)
    end

    local origPrerender = P.prerender
    function P:prerender()
        origPrerender(self)
        local btn = self.cpTrackButton
        if not btn then return end
        local recipe = self.logic and self.logic:getRecipe()
        btn:setVisible(recipe ~= nil)
        btn.textureColor = CraftPlanner.isTracked(self.player, recipe) and COLOR_TRACKED or COLOR_IDLE
    end
end

Events.OnGameBoot.Add(patchNeat)
