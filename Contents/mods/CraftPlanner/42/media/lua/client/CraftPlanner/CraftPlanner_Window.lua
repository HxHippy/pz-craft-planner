-- Craft Planner: the window. Search on top, then one plan per tracked recipe:
-- tools to hold, stuff to gather, and the crafts in the order you do them.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTickBox"
require "CraftPlanner/CraftPlanner_Plan"

CraftPlanner = CraftPlanner or {}
local Graph = CraftPlanner.Graph
local Plan = CraftPlanner.Plan

local FONT = UIFont.Small
local FONT_H = getTextManager():getFontHeight(FONT)
local ROW_H = math.max(18, FONT_H + 4)
local INDENT = 14
local REFRESH_MS = 1000

local TEX_TICK = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
local TEX_CROSS = getTexture("media/ui/inventoryPanes/Tickbox_Cross.png")

local COLORS = {
    met     = { 0.55, 0.9, 0.55 },
    unmet   = { 0.95, 0.55, 0.5 },
    after   = { 0.95, 0.8, 0.45 },
    unknown = { 0.7, 0.7, 0.7 },
    plain   = { 0.9, 0.9, 0.9 },
}

CraftPlannerList = ISScrollingListBox:derive("CraftPlannerList")

function CraftPlannerList:doDrawItem(y, entry, alt)
    local row = entry.item
    local w = self:getWidth()
    local textY = y + (ROW_H - FONT_H) / 2
    if self.mouseoverselected == entry.index and self:isMouseOver() and not self:isMouseOverScrollBar()
        and (row.cycleKey or row.result or row.trackRecipe) then
        self:drawRect(0, y, w, ROW_H, 0.15, 1, 1, 1)
    end

    if row.header then
        self:drawRect(0, y, w, ROW_H, 0.45, 0.12, 0.12, 0.12)
        local c = COLORS[row.status or "plain"] or COLORS.plain
        self:drawText(row.text, 6, textY, c[1], c[2], c[3], 1, FONT)
        return y + ROW_H
    end
    if row.section then
        self:drawText(row.text, 8, textY, 0.6, 0.75, 0.95, 1, FONT)
        return y + ROW_H
    end

    local x = 10 + (row.depth or 1) * INDENT
    if row.texture then self:drawTextureScaledAspect(row.texture, x, y + ROW_H / 2 - 8, 16, 16, 1, 1, 1, 1) end
    x = x + 20

    local c = COLORS[row.status or "plain"] or COLORS.plain
    local label = row.text
    if row.cycleKey and row.alts and row.alts > 1 then label = label .. "  " .. getText("UI_CraftPlanner_Alts", row.alts - 1) end
    if row.note then label = label .. "  " .. row.note end
    self:drawText(label, x, textY, c[1], c[2], c[3], 1, FONT)

    local right = w - 24
    local tex = (row.status == "met" and TEX_TICK) or (row.status == "unmet" and TEX_CROSS) or nil
    if tex then self:drawTextureScaled(tex, right, y + ROW_H / 2 - 7, 14, 14, 1, 1, 1, 1) end
    local tail = row.need and (row.have .. "/" .. row.need) or row.tail
    if tail then
        local tw = getTextManager():MeasureStringX(FONT, tail)
        self:drawText(tail, right - tw - 6, textY, c[1], c[2], c[3], 1, FONT)
    end
    return y + ROW_H
end

function CraftPlannerList:onRightMouseUp(x, y)
    local entry = self.items[self:rowAt(x, y)]
    if not entry or not entry.item.target then return end
    local context = ISContextMenu.get(self.parent.playerNum, getMouseX(), getMouseY())
    context:addOption(getText("UI_CraftPlanner_Untrack"), entry.item.target, CraftPlanner.untrack, self.parent.playerObj)
end

---------------------------------------------------------------------------------------------

CraftPlannerWindow = ISCollapsableWindow:derive("CraftPlannerWindow")

function CraftPlannerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + 4

    self.search = ISTextEntryBox:new("", 6, top, self.width - 12, FONT_H + 6)
    self.search:initialise()
    self.search:instantiate()
    self.search:setClearButton(true)
    self.search.onTextChangeFunction = CraftPlannerWindow.onSearchChanged
    self.search.target = self
    self.search:setTooltip(getText("UI_CraftPlanner_SearchTip"))
    self.search:setAnchorRight(true)
    self:addChild(self.search)
    top = top + self.search:getHeight() + 4

    self.nearby = ISTickBox:new(6, top, self.width - 12, ROW_H, "", self, CraftPlannerWindow.onNearbyToggled)
    self.nearby:initialise()
    self.nearby:addOption(getText("UI_CraftPlanner_CountNearby"))
    self.nearby:setSelected(1, CraftPlanner.getState(self.playerObj).nearby ~= false)
    self:addChild(self.nearby)
    top = top + ROW_H + 4

    self.list = CraftPlannerList:new(0, top, self.width, self.height - top - self:resizeWidgetHeight())
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.drawBorder = false
    self.list.backgroundColor.a = 0
    self.list:setAnchorRight(true)
    self.list:setAnchorBottom(true)
    self.list:setOnMouseDownFunction(self, CraftPlannerWindow.onRowClicked)
    self:addChild(self.list)

    self:refresh()
end

function CraftPlannerWindow:onSearchChanged()
    self.lastRefresh = 0
end

function CraftPlannerWindow:onNearbyToggled(index, selected)
    CraftPlanner.getState(self.playerObj).nearby = selected
    self.lastRefresh = 0
end

function CraftPlannerWindow:onRowClicked(row)
    if row.trackRecipe then
        CraftPlanner.track(row.trackRecipe, self.playerObj)
    elseif row.result then
        CraftPlanner.track(row.result, self.playerObj)
        self.search:setText("")
    elseif row.cycleKey then
        -- Click cycles through the other ways to satisfy this line.
        local cur = self.choices[row.cycleKey] or row.cycleCurrent or 1
        self.choices[row.cycleKey] = (cur % row.alts) + 1
    end
    self.lastRefresh = 0
end

local STATUS_TEXT = {
    ready = "UI_CraftPlanner_Ready",
    after = "UI_CraftPlanner_Crafting",
    blocked = "UI_CraftPlanner_Gathering",
}

function CraftPlannerWindow:addPlan(target, counter)
    local list = self.list
    local plan = Plan.build(self.playerObj, target, counter, self.choices)
    if not plan then return end
    list:addItem("", {
        header = true, target = target, status = plan.state == "ready" and "met" or "plain",
        text = Graph.recipeName(plan.target) .. "  -  " .. getText(STATUS_TEXT[plan.state]),
    })

    if #plan.tools > 0 then
        list:addItem("", { section = true, text = getText("UI_CraftPlanner_Tools") })
        for _, tool in ipairs(plan.tools) do
            local shown = tool.pick or tool.items[1]
            local met = tool.have >= tool.need
            list:addItem("", {
                text = shown:getDisplayName(), texture = shown:getNormalTexture(),
                status = met and "met" or "unmet", alts = #tool.items,
                cycleKey = (not met and #tool.items > 1) and tool.key or nil, cycleCurrent = tool.pickIndex,
            })
            if not met and tool.via then
                list:addItem("", {
                    depth = 2, text = getText("UI_CraftPlanner_CraftVia", Graph.recipeName(tool.via)),
                    texture = tool.via:getIconTexture(), status = "after", trackRecipe = tool.via:getName(),
                })
            end
        end
    end

    local missing = 0
    for _, g in ipairs(plan.gather) do if g.have < g.need then missing = missing + 1 end end
    for _, f in ipairs(plan.fluids) do if not f.any and f.have + 0.001 < f.need then missing = missing + 1 end end
    if #plan.gather > 0 or #plan.fluids > 0 then
        list:addItem("", { section = true, text = getText("UI_CraftPlanner_Gather", missing) })
        for _, g in ipairs(plan.gather) do
            list:addItem("", {
                text = g.item:getDisplayName(), texture = g.item:getNormalTexture(),
                have = g.have, need = g.need, status = g.have >= g.need and "met" or "unmet",
                alts = g.alts, cycleKey = g.alts and g.key or nil, cycleCurrent = g.choice,
            })
        end
        for _, f in ipairs(plan.fluids) do
            list:addItem("", {
                text = f.name,
                status = f.any and "unknown" or ((f.have + 0.001 >= f.need) and "met" or "unmet"),
                tail = f.any and string.format("%.1fL", f.need) or string.format("%.1f/%.1fL", f.have, f.need),
            })
        end
    end

    list:addItem("", { section = true, text = getText("UI_CraftPlanner_Steps") })
    for i, step in ipairs(plan.steps) do
        local notes = {}
        if step.unlearned then table.insert(notes, getText("UI_CraftPlanner_NotLearned")) end
        if #step.skills > 0 then table.insert(notes, "[" .. table.concat(step.skills, ", ") .. "]") end
        local status = (step.state == "ready" and "met") or (step.state == "after" and "after") or "unmet"
        local canCycle = (not step.isTarget) and step.alts and step.alts > 1
        list:addItem("", {
            text = i .. ". " .. Graph.recipeName(step.recipe) .. (step.times > 1 and (" x" .. step.times) or ""),
            texture = step.recipe:getIconTexture(), status = status,
            tail = step.state == "after" and getText("UI_CraftPlanner_AfterSteps") or nil,
            note = #notes > 0 and table.concat(notes, " ") or nil,
            alts = canCycle and step.alts or nil,
            cycleKey = canCycle and step.key or nil, cycleCurrent = step.altIndex,
        })
    end
end

function CraftPlannerWindow:refresh()
    self.lastRefresh = getTimestampMs()
    local scroll = self.list:getYScroll()
    self.list:clear()

    local query = self.search:getText()
    if query and #query >= 2 then
        local results = Graph.search(query, 40)
        self.list:addItem("", { header = true, text = getText("UI_CraftPlanner_Results", #results) })
        for _, res in ipairs(results) do
            self.list:addItem("", { depth = 0, text = res.display, texture = res.recipe:getIconTexture(), result = res.name })
        end
        return
    end

    local state = CraftPlanner.getState(self.playerObj)
    if #state.targets == 0 then
        self.list:addItem("", { section = true, text = getText("UI_CraftPlanner_Empty") })
        return
    end

    local counter = Graph.newCounter(self.playerObj, state.nearby ~= false)
    for _, target in ipairs(state.targets) do self:addPlan(target, counter) end
    self.list:setYScroll(scroll)
end

function CraftPlannerWindow:update()
    ISCollapsableWindow.update(self)
    if getTimestampMs() - (self.lastRefresh or 0) >= REFRESH_MS then self:refresh() end
end

function CraftPlannerWindow:close()
    CraftPlanner.setVisible(self.playerObj, false)
end

function CraftPlannerWindow:new(x, y, playerObj)
    local o = ISCollapsableWindow.new(self, x, y, 440, 520)
    o.title = getText("UI_CraftPlanner_Title")
    o.playerObj = playerObj
    o.playerNum = playerObj:getPlayerNum()
    o.choices = {}
    o.lastRefresh = 0
    o:setResizable(true)
    return o
end
