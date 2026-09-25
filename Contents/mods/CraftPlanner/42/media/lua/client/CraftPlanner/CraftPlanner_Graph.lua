-- Craft Planner: recipe graph.
-- Indexes every craft and build recipe by the items it produces, and flags the producers a
-- planner shouldn't reach for blindly: byproducts, chance drops, and reversible conversions
-- like pack/unpack or tie/untie.

CraftPlanner = CraftPlanner or {}
local Graph = {}
CraftPlanner.Graph = Graph

local recipesByName   -- name -> CraftRecipe
local producersByType -- item full type -> { {recipe=, yield=, primary=, chance=, reversible=}, ... }

local function eachJava(list, fn)
    if not list then return end
    for i = 0, list:size() - 1 do fn(list:get(i)) end
end

-- Item types a recipe consumes (tools and kept items don't count).
local function consumedTypes(recipe)
    local set = {}
    eachJava(recipe:getInputs(), function(input)
        if input:getResourceType() ~= ResourceType.Item or input:isKeep() or input:isTool() then return end
        eachJava(input:getPossibleInputItems(), function(item) set[item:getFullName()] = true end)
    end)
    return set
end

function Graph.index()
    if recipesByName then return end
    recipesByName, producersByType = {}, {}
    local sm = getScriptManager()
    local consumes, produces = {}, {}

    local function add(recipe)
        local name = recipe:getName()
        if recipesByName[name] then return end
        recipesByName[name] = recipe
        consumes[name] = consumedTypes(recipe)
        produces[name] = {}
        local first = true
        eachJava(recipe:getOutputs(), function(out)
            if out:getResourceType() ~= ResourceType.Item then return end
            local yield = math.max(1, out:getIntAmount())
            local chance = out:getChance()
            eachJava(out:getPossibleResultItems(), function(item)
                local t = item:getFullName()
                produces[name][t] = true
                producersByType[t] = producersByType[t] or {}
                table.insert(producersByType[t], {
                    recipe = recipe, yield = yield, primary = first,
                    chance = (chance and chance > 0) and chance or 1,
                })
            end)
            first = false
        end)
    end
    eachJava(sm:getAllCraftRecipes(), add)
    eachJava(sm:getAllBuildableRecipes(), add)

    -- A producer is reversible when some other recipe turns its output back into its inputs.
    local consumersOf = {}
    for name, set in pairs(consumes) do
        for t in pairs(set) do
            consumersOf[t] = consumersOf[t] or {}
            table.insert(consumersOf[t], name)
        end
    end
    for t, list in pairs(producersByType) do
        for _, p in ipairs(list) do
            local ins = consumes[p.recipe:getName()]
            for _, other in ipairs(consumersOf[t] or {}) do
                for out in pairs(produces[other]) do
                    if ins[out] then p.reversible = true break end
                end
                if p.reversible then break end
            end
        end
    end
end

function Graph.getRecipe(name)
    Graph.index()
    return recipesByName[name]
end

function Graph.recipeName(recipe)
    return getText(recipe:getTranslationName())
end

function Graph.producersOf(fullType)
    Graph.index()
    return producersByType[fullType] or {}
end

-- Case-insensitive substring search over every recipe's display name.
function Graph.search(query, limit)
    Graph.index()
    query = string.lower(query or "")
    local out = {}
    if #query < 2 then return out end
    for name, recipe in pairs(recipesByName) do
        local display = Graph.recipeName(recipe)
        if string.find(string.lower(display), query, 1, true) then
            table.insert(out, { name = name, display = display, recipe = recipe })
        end
    end
    table.sort(out, function(a, b) return a.display < b.display end)
    while #out > (limit or 40) do table.remove(out) end
    return out
end

---------------------------------------------------------------------------------------------
-- Counting

local Counter = {}
Counter.__index = Counter

function Graph.newCounter(playerObj, includeNearby)
    local c = setmetatable({ cache = {}, containers = {} }, Counter)
    if includeNearby then
        eachJava(ISInventoryPaneContextMenu.getContainers(playerObj), function(con)
            table.insert(c.containers, con)
        end)
    else
        table.insert(c.containers, playerObj:getInventory())
    end
    return c
end

-- Liters of any of the given fluids across every fluid container the counter can see.
function Counter:fluid(fluids)
    local key = {}
    for _, f in ipairs(fluids) do table.insert(key, f:getFluidTypeString()) end
    key = "fluid:" .. table.concat(key, ",")
    if self.cache[key] then return self.cache[key] end
    local liters = 0
    local function scan(item)
        local fc = item:getFluidContainer()
        if fc and not fc:isEmpty() then
            for _, f in ipairs(fluids) do liters = liters + fc:getSpecificFluidAmount(f) end
        end
        return false
    end
    for _, con in ipairs(self.containers) do con:getAllEvalRecurse(scan) end
    self.cache[key] = liters
    return liters
end

function Counter:count(fullType)
    local n = self.cache[fullType]
    if n then return n end
    n = 0
    for _, con in ipairs(self.containers) do n = n + con:getCountTypeRecurse(fullType) end
    self.cache[fullType] = n
    return n
end
