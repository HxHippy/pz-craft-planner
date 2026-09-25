-- Craft Planner: state, hotkey, right-click entry points, and auto-clear when the thing gets made.
-- Tracked recipes live in player mod data, so they survive relogs and server restarts.

require "CraftPlanner/CraftPlanner_Graph"
require "CraftPlanner/CraftPlanner_Plan"
require "CraftPlanner/CraftPlanner_Window"
require "CraftPlanner/CraftPlanner_Buttons"
require "Entity/TimedActions/ISHandcraftAction"
require "BuildingObjects/TimedActions/ISBuildAction"

CraftPlanner = CraftPlanner or {}
CraftPlanner.windows = {}
local Graph = CraftPlanner.Graph

local options = PZAPI.ModOptions:create("CraftPlanner", getText("UI_CraftPlanner_Title"))
local optToggle = options:addKeyBind("toggle", getText("UI_CraftPlanner_Keybind"), Keyboard.KEY_K)
local optAutoRemove = options:addTickBox("autoRemove", getText("UI_CraftPlanner_AutoRemove"), true)

function CraftPlanner.getState(playerObj)
    local md = playerObj:getModData()
    md.CraftPlanner = md.CraftPlanner or { targets = {}, visible = false, nearby = true }
    return md.CraftPlanner
end

local function localPlayer()
    return getSpecificPlayer(0)
end

function CraftPlanner.setVisible(playerObj, visible)
    local num = playerObj:getPlayerNum()
    CraftPlanner.getState(playerObj).visible = visible
    local win = CraftPlanner.windows[num]
    if visible then
        if not win then
            win = CraftPlannerWindow:new(getCore():getScreenWidth() - 460, 120, playerObj)
            win:initialise()
            win:instantiate()
            CraftPlanner.windows[num] = win
        end
        win:addToUIManager()
        win:setVisible(true)
        win.lastRefresh = 0
    elseif win then
        win:setVisible(false)
        win:removeFromUIManager()
    end
end

function CraftPlanner.toggle(playerObj)
    CraftPlanner.setVisible(playerObj, not CraftPlanner.getState(playerObj).visible)
end

function CraftPlanner.track(recipeName, playerObj)
    playerObj = playerObj or localPlayer()
    if not playerObj or not Graph.getRecipe(recipeName) then return end
    local state = CraftPlanner.getState(playerObj)
    for _, name in ipairs(state.targets) do
        if name == recipeName then CraftPlanner.setVisible(playerObj, true) return end
    end
    table.insert(state.targets, recipeName)
    CraftPlanner.setVisible(playerObj, true)
end

function CraftPlanner.untrack(recipeName, playerObj)
    playerObj = playerObj or localPlayer()
    if not playerObj then return end
    local targets = CraftPlanner.getState(playerObj).targets
    for i = #targets, 1, -1 do
        if targets[i] == recipeName then table.remove(targets, i) end
    end
    local win = CraftPlanner.windows[playerObj:getPlayerNum()]
    if win then win.lastRefresh = 0 end
end

function CraftPlanner.onCrafted(character, recipeName)
    if not character or not recipeName or not character:isLocalPlayer() then return end
    if not optAutoRemove:getValue() then return end
    local state = CraftPlanner.getState(character)
    for _, name in ipairs(state.targets) do
        if name == recipeName then
            CraftPlanner.untrack(recipeName, character)
            local recipe = Graph.getRecipe(recipeName)
            HaloTextHelper.addGoodText(character, getText("UI_CraftPlanner_Done", recipe and Graph.recipeName(recipe) or recipeName))
            return
        end
    end
end

-- Crafts and builds both finish in perform() on the crafting client, SP and MP alike.
local origHandcraftPerform = ISHandcraftAction.perform
function ISHandcraftAction:perform()
    local character, recipe = self.character, self.craftRecipe
    origHandcraftPerform(self)
    if recipe then CraftPlanner.onCrafted(character, recipe:getName()) end
end

local origBuildPerform = ISBuildAction.perform
function ISBuildAction:perform()
    local character, recipe = self.character, self.item and self.item.craftRecipe
    origBuildPerform(self)
    if recipe then CraftPlanner.onCrafted(character, recipe:getName()) end
end

-- Right-click any item: "Track how to make <item>", one entry per recipe that produces it.
local function onInventoryContext(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    local actual = ISInventoryPane.getActualItems(items)
    local item = actual[1]
    if not item then return end
    local producers = Graph.producersOf(item:getFullType())
    if #producers == 0 then return end

    local label = getText("UI_CraftPlanner_TrackMake", item:getDisplayName())
    if #producers == 1 then
        context:addOption(label, producers[1].recipe:getName(), CraftPlanner.track, playerObj)
        return
    end
    local option = context:addOption(label)
    local sub = context:getNew(context)
    context:addSubMenu(option, sub)
    local seen = {}
    for _, p in ipairs(producers) do
        local name = p.recipe:getName()
        if not seen[name] then
            seen[name] = true
            sub:addOption(Graph.recipeName(p.recipe), name, CraftPlanner.track, playerObj)
        end
    end
end

local function onKeyPressed(key)
    if key ~= optToggle:getValue() or key == 0 then return end
    local playerObj = localPlayer()
    if playerObj and not playerObj:isDead() then CraftPlanner.toggle(playerObj) end
end

local function onCreatePlayer(playerNum, playerObj)
    if CraftPlanner.getState(playerObj).visible then CraftPlanner.setVisible(playerObj, true) end
end

local function onPlayerDeath(playerObj)
    if not playerObj:isLocalPlayer() then return end
    local win = CraftPlanner.windows[playerObj:getPlayerNum()]
    if win then
        win:setVisible(false)
        win:removeFromUIManager()
        CraftPlanner.windows[playerObj:getPlayerNum()] = nil
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onInventoryContext)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
