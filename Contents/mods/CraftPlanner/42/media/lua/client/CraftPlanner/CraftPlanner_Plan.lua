-- Craft Planner: the planner.
-- Walks a recipe down to raw materials against a virtual copy of what the player owns, so
-- stuff already in the bag is spent first and only real shortfalls turn into gathering or
-- sub-crafts. Output is three lists: tools to hold, things to gather, crafts in order.
--
-- Rules that keep plans sane:
--  * Missing tools never recurse. They show as "find, or craft via X", and X can be tracked
--    as its own goal.
--  * Byproducts, chance drops, and reversible conversions (unpack, untie, dismantle) are only
--    used when the player can already do them with what they have.
--  * Chains stop at MAX_DEPTH, and anything deeper is listed as something to gather.

require "CraftPlanner/CraftPlanner_Graph"

CraftPlanner = CraftPlanner or {}
local Graph = CraftPlanner.Graph
local Plan = {}
CraftPlanner.Plan = Plan

local MAX_DEPTH = 5
local RANK = { ready = 1, after = 2, blocked = 3 }

local function eachJava(list, fn)
    if not list then return end
    for i = 0, list:size() - 1 do fn(list:get(i), i + 1) end
end

local function worst(a, b)
    return RANK[b] > RANK[a] and b or a
end

local function isToolLike(input)
    return input:isKeep() or input:isTool()
end

local function isKnown(playerObj, recipe)
    return not recipe:needToBeLearn() or playerObj:isRecipeActuallyKnown(recipe)
end

local function missingSkills(playerObj, recipe)
    local parts = {}
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local req = recipe:getRequiredSkill(i)
        if playerObj:getPerkLevel(req:getPerk()) < req:getLevel() then
            table.insert(parts, req:getPerk():getName() .. " " .. req:getLevel())
        end
    end
    return parts
end

-- Items of `item` an input needs for `times` crafts. Drainables are specified in uses.
local function itemsNeeded(input, item, times)
    local amount = math.max(1, input:getIntAmount())
    if not input:isItemCount() and input:isUsesPartialItem(item) then
        local delta = item:getUseDelta()
        if delta and delta > 0 then return math.max(1, math.ceil(amount * times * delta - 0.0001)) end
        return 1
    end
    return amount * times
end

local function inputItems(input)
    local items = {}
    eachJava(input:getPossibleInputItems(), function(it) table.insert(items, it) end)
    return items
end

-- Can this recipe run `crafts` times from what's in the pool right now, tools included?
local function doableNow(recipe, crafts, avail)
    local ok = true
    eachJava(recipe:getInputs(), function(input)
        if not ok or input:getResourceType() ~= ResourceType.Item then return end
        local items = inputItems(input)
        if #items == 0 then return end
        local have = 0
        for _, it in ipairs(items) do have = have + avail(it:getFullName()) end
        local need = isToolLike(input) and 1 or itemsNeeded(input, items[1], crafts)
        if have < need then ok = false end
    end)
    return ok
end

-- Producers worth suggesting for `short` of fullType, best first.
local function candidates(playerObj, fullType, short, avail)
    local list = {}
    for _, p in ipairs(Graph.producersOf(fullType)) do
        local crafts = math.ceil(short / p.yield)
        local now = doableNow(p.recipe, crafts, avail)
        local clean = p.primary and p.chance >= 1 and not p.reversible
        if now or clean then
            table.insert(list, { p = p, now = now, known = isKnown(playerObj, p.recipe), crafts = crafts })
        end
    end
    table.sort(list, function(a, b)
        if a.now ~= b.now then return a.now end
        if a.known ~= b.known then return a.known end
        if a.p.primary ~= b.p.primary then return a.p.primary end
        local na, nb = a.p.recipe:getInputs():size(), b.p.recipe:getInputs():size()
        if na ~= nb then return na < nb end
        return a.p.recipe:getName() < b.p.recipe:getName()
    end)
    return list
end

-- choices: key -> chosen index, set by the player clicking a row to cycle alternatives.
function Plan.build(playerObj, targetName, counter, choices)
    local recipe = Graph.getRecipe(targetName)
    if not recipe then return nil end

    local pool = {}
    local function avail(t)
        if pool[t] == nil then pool[t] = counter:count(t) end
        return pool[t]
    end

    local plan = { tools = {}, gather = {}, fluids = {}, steps = {}, target = recipe }
    local toolsByKey, gatherByType, stepsByName, fluidsByName = {}, {}, {}, {}

    local function addGather(item, need, have)
        local t = item:getFullName()
        local g = gatherByType[t]
        if not g then
            g = { item = item, need = 0, have = 0 }
            gatherByType[t] = g
            table.insert(plan.gather, g)
        end
        g.need = g.need + need
        g.have = g.have + have
        return g
    end

    local resolveRecipe -- forward

    -- Crafts `short` of item via its best producer. Returns the resulting step state, or nil
    -- when there's no sensible way to make it from here.
    local function craftShortfall(item, short, depth, ancestors, key)
        local t = item:getFullName()
        if ancestors[t] or depth >= MAX_DEPTH then return nil end
        local list = candidates(playerObj, t, short, avail)
        if #list == 0 then return nil end
        local idx = choices[key] or 1
        if idx > #list then idx = 1 end
        local c = list[idx]
        local nextAnc = {}
        for k in pairs(ancestors) do nextAnc[k] = true end
        nextAnc[t] = true
        local state = resolveRecipe(c.p.recipe, c.crafts, depth + 1, nextAnc, key, #list, idx)
        -- Leftovers from the batch are available to later inputs.
        pool[t] = avail(t) + c.crafts * c.p.yield - short
        return state
    end

    local function addTool(input, items, ikey)
        local tkey = items[1]:getFullName() .. "#" .. #items
        local tool = toolsByKey[tkey]
        if tool then return tool end
        local have = 0
        for _, it in ipairs(items) do have = have + avail(it:getFullName()) end
        tool = { items = items, need = 1, have = have, key = ikey }
        toolsByKey[tkey] = tool
        table.insert(plan.tools, tool)
        if have >= 1 then return tool end

        -- Missing: default to an alternative that can actually be crafted, and name the recipe.
        local pickIdx = choices[ikey]
        local via
        if not pickIdx or pickIdx > #items then
            pickIdx = 1
            for k, it in ipairs(items) do
                local list = candidates(playerObj, it:getFullName(), 1, avail)
                if #list > 0 then pickIdx, via = k, list[1].p.recipe break end
            end
        else
            local list = candidates(playerObj, items[pickIdx]:getFullName(), 1, avail)
            via = list[1] and list[1].p.recipe
        end
        tool.pick, tool.pickIndex, tool.via = items[pickIdx], pickIdx, via
        return tool
    end

    resolveRecipe = function(r, times, depth, ancestors, key, altCount, altIndex)
        local state = "ready"
        eachJava(r:getInputs(), function(input, i)
            local ikey = key .. "/i" .. i
            local rtype = input:getResourceType()

            if rtype == ResourceType.Fluid then
                local fluids = {}
                eachJava(input:getPossibleInputFluids(), function(f) table.insert(fluids, f) end)
                local name = input:getInputFluidFilterDisplayName() or "Fluid"
                local fl = fluidsByName[name]
                if not fl then
                    fl = { name = name, need = 0, have = counter:fluid(fluids) }
                    fluidsByName[name] = fl
                    table.insert(plan.fluids, fl)
                end
                fl.need = fl.need + input:getAmount() * (isToolLike(input) and 1 or times)
                -- "Any fluid" inputs have no list to count against, so they never block.
                if #fluids == 0 then fl.any = true
                elseif fl.have + 0.001 < fl.need then state = "blocked" end
                return
            end
            if rtype ~= ResourceType.Item then return end

            local items = inputItems(input)
            if #items == 0 then return end

            if isToolLike(input) then
                local tool = addTool(input, items, ikey)
                if tool.have < tool.need then state = "blocked" end
                return
            end

            -- Default alternative: whichever the player has most of right now.
            local choice = choices[ikey]
            if not choice or choice > #items then
                choice = 1
                for k, it in ipairs(items) do
                    if avail(it:getFullName()) > avail(items[choice]:getFullName()) then choice = k end
                end
            end
            local item = items[choice]
            local t = item:getFullName()
            local need = itemsNeeded(input, item, times)
            local take = math.min(avail(t), need)
            pool[t] = avail(t) - take
            local short = need - take

            local s = short > 0 and craftShortfall(item, short, depth, ancestors, ikey .. "/p") or nil
            local g
            if s then
                state = worst(state, s == "blocked" and "blocked" or "after")
                if take > 0 then g = addGather(item, take, take) end
            else
                g = addGather(item, need, take)
                if short > 0 then state = "blocked" end
            end
            if g and #items > 1 then g.alts, g.key, g.choice = #items, ikey, choice end
        end)

        local name = r:getName()
        local step = stepsByName[name]
        if step then
            step.times = step.times + times
            step.state = worst(step.state, state)
        else
            step = {
                recipe = r, times = times, state = state, key = key, alts = altCount,
                altIndex = altIndex or 1, unlearned = not isKnown(playerObj, r),
                skills = missingSkills(playerObj, r), isTarget = depth == 0,
            }
            stepsByName[name] = step
            table.insert(plan.steps, step)
        end
        return state
    end

    plan.state = resolveRecipe(recipe, 1, 0, {}, targetName, 1, 1)
    -- Missing stuff first, then what's covered.
    table.sort(plan.gather, function(a, b)
        local ma, mb = a.have < a.need, b.have < b.need
        if ma ~= mb then return ma end
        return a.item:getDisplayName() < b.item:getDisplayName()
    end)
    table.sort(plan.tools, function(a, b)
        local ma, mb = a.have < a.need, b.have < b.need
        if ma ~= mb then return ma end
        return (a.pick or a.items[1]):getDisplayName() < (b.pick or b.items[1]):getDisplayName()
    end)
    return plan
end
