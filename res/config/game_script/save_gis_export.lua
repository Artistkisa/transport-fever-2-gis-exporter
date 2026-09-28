local outputRoot = os.getenv("USERPROFILE") .. "/VSC/transport-fever-2-save-analysis/export/"
local runner
local finished = false

local function escape(value)
    return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"')
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        :gsub("[%z\1-\8\11\12\14-\31]", function(character)
            return string.format("\\u%04x", string.byte(character))
        end)
end

local function encode(value)
    if value == nil then return "null" end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) == "string" then return '"' .. escape(value) .. '"' end
    if type(value) ~= "table" then return '"' .. escape(value) .. '"' end
    local parts = {}
    if #value > 0 then
        for index = 1, #value do parts[#parts + 1] = encode(value[index]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
        parts[#parts + 1] = '"' .. escape(key) .. '":' .. encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function field(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function vector(value)
    if value == nil then return nil end
    local x = field(value, "x") or field(value, 1)
    local y = field(value, "y") or field(value, 2)
    local z = field(value, "z") or field(value, 3)
    if x == nil or y == nil then return nil end
    return { x, y, z or 0 }
end

local function sequence(value)
    local result = {}
    if value ~= nil then
        for index = 1, #value do result[#result + 1] = value[index] end
    end
    return result
end

local function mapping(value)
    local result = {}
    if value ~= nil then
        for key, item in pairs(value) do
            result[tostring(key)] = item
        end
    end
    return result
end

local function exportCategory(fileName, componentType, build)
    local file = assert(io.open(outputRoot .. fileName .. ".jsonl", "wb"))
    local count = 0
    local errors = 0
    api.engine.forEachEntityWithComponent(function(entity)
        local ok, row = pcall(build, entity)
        if ok and row then
            file:write(encode(row), "\n")
            count = count + 1
        else
            errors = errors + 1
        end
    end, componentType)
    file:close()
    return { count = count, errors = errors }
end

local function export()
    local types = api.type.ComponentType
    local function component(entity, kind)
        return api.engine.getComponent(entity, kind)
    end
    local function name(entity)
        return field(component(entity, types.NAME), "name")
    end
    local function legacy(entity)
        return game.interface.getEntity(entity)
    end
    local function position(entity)
        return vector(field(legacy(entity), "position"))
    end

    local summary = {}
    summary.towns = exportCategory("towns", types.TOWN, function(entity)
        local town = component(entity, types.TOWN)
        return { id = entity, name = name(entity), position = position(entity),
            sizeFactor = field(town, "sizeFactor"), growthTendency = field(town, "growthTendency") }
    end)
    coroutine.yield()
    summary.station_groups = exportCategory("station_groups", types.STATION_GROUP, function(entity)
        return { id = entity, name = name(entity), position = position(entity),
            stations = sequence(field(component(entity, types.STATION_GROUP), "stations")) }
    end)
    coroutine.yield()
    summary.stations = exportCategory("stations", types.STATION, function(entity)
        local station = component(entity, types.STATION)
        return { id = entity, name = name(entity), position = position(entity),
            stationGroup = field(legacy(entity), "stationGroup"), cargo = field(station, "cargo"),
            terminalCount = #(field(station, "terminals") or {}) }
    end)
    coroutine.yield()
    summary.platforms = exportCategory("platforms", types.STATION, function(entity)
        local station = component(entity, types.STATION)
        local group = field(legacy(entity), "stationGroup")
        local terminals = field(station, "terminals") or {}
        local rows = {}
        for index, terminal in ipairs(terminals) do
            local lines = {}
            local ok, found = pcall(function()
                return api.engine.system.line.getLineStopsForTerminal(entity, terminals[index])
            end)
            if ok and found then lines = mapping(found) end
            local waitingCount = 0
            api.engine.forEachEntityWithComponent(function(person)
                local waiting = component(person, types.SIM_PERSON_AT_TERMINAL)
                for _, edge in ipairs(sequence(field(terminal, "personEdges"))) do
                    if tostring(field(waiting, "edgeId")) == tostring(edge) then
                        waitingCount = waitingCount + 1
                    end
                end
            end, types.SIM_PERSON_AT_TERMINAL)
            rows[#rows + 1] = {
                index = index - 1,
                tag = field(terminal, "tag"),
                vehicleNodeId = field(terminal, "vehicleNodeId"),
                personNodes = sequence(field(terminal, "personNodes")),
                personEdges = sequence(field(terminal, "personEdges")),
                lineIds = lines,
                waitingCount = waitingCount,
            }
        end
        return { id = entity, name = name(entity), stationGroup = group,
            platformCount = #rows, platforms = rows }
    end)
    coroutine.yield()
    summary.lines = exportCategory("lines", types.LINE, function(entity)
        local stops = sequence(field(legacy(entity), "stops"))
        return { id = entity, name = name(entity), stops = stops, stopCount = #stops }
    end)
    coroutine.yield()
    summary.nodes = exportCategory("nodes", types.BASE_NODE, function(entity)
        return { id = entity, position = vector(field(component(entity, types.BASE_NODE), "position")) or position(entity) }
    end)
    coroutine.yield()
    summary.edges = exportCategory("edges", types.BASE_EDGE, function(entity)
        local edge = component(entity, types.BASE_EDGE)
        local old = legacy(entity)
        local track = component(entity, types.BASE_EDGE_TRACK)
        local street = component(entity, types.BASE_EDGE_STREET)
        return { id = entity, node0 = field(edge, "node0") or field(old, "node0"),
            node1 = field(edge, "node1") or field(old, "node1"),
            track = track ~= nil, street = street ~= nil,
            maxSpeed = field(track, "maxSpeed") or field(street, "maxSpeed"),
            typeIndex = field(track, "typeIndex") or field(street, "typeIndex") }
    end)
    coroutine.yield()
    summary.industries = exportCategory("industries", types.SIM_BUILDING, function(entity)
        return { id = entity, name = name(entity), position = position(entity) }
    end)
    coroutine.yield()
    summary.vehicles = exportCategory("vehicles", types.TRANSPORT_VEHICLE, function(entity)
        local vehicle = component(entity, types.TRANSPORT_VEHICLE)
        local ok, info = pcall(function()
            return api.engine.system.transportVehicleSystem.getInfo(entity)
        end)
        return { id = entity, name = name(entity), position = position(entity),
            line = field(vehicle, "line"), carrier = field(vehicle, "carrier"),
            stopIndex = field(vehicle, "stopIndex"),
            vehicleInfo = ok and {
                name = field(info, "name"), fileName = field(info, "fileName"),
                speed = field(info, "speed"), capacity = field(info, "capacity"),
                maxSpeed = field(info, "maxSpeed")
            } or nil }
    end)
    coroutine.yield()
    summary.constructions = exportCategory("constructions", types.CONSTRUCTION, function(entity)
        local construction = component(entity, types.CONSTRUCTION)
        return { id = entity, name = name(entity), position = position(entity),
            fileName = field(construction, "fileName"),
            stations = sequence(field(construction, "stations")),
            simBuildings = sequence(field(construction, "simBuildings")) }
    end)
    coroutine.yield()
    summary.terrain = exportCategory("terrain", types.TERRAIN, function(entity)
        local terrain = component(entity, types.TERRAIN)
        return { id = entity, tileSize = vector(field(terrain, "size")),
            waterLevel = field(terrain, "waterLevel"),
            baseLevels = field(terrain, "baseLevels"),
            highLevels = field(terrain, "highLevels") }
    end)
    coroutine.yield()
    summary.terrain_tiles = exportCategory("terrain_tiles", types.TERRAIN_TILE, function(entity)
        local tile = component(entity, types.TERRAIN_TILE)
        return { id = entity, terrainEntity = field(tile, "terrainEntity"),
            gridPosition = vector(field(tile, "position")) }
    end)
    coroutine.yield()
    summary.heightmaps = exportCategory("heightmaps", types.TERRAIN_TILE_HEIGHTMAP, function(entity)
        local heightmap = component(entity, types.TERRAIN_TILE_HEIGHTMAP)
        return { id = entity, vertices = sequence(field(heightmap, "vertices")) }
    end)
    coroutine.yield()
    summary.water = exportCategory("water", types.WATER_MESH, function(entity)
        local water = component(entity, types.WATER_MESH)
        local contours = sequence(field(water, "contours"))
        local contourRows = {}
        for _, contour in ipairs(contours) do
            contourRows[#contourRows + 1] = {
                vertices = sequence(field(contour, "vertices")),
            }
        end
        return { id = entity, waterLevel = field(water, "waterLevel"),
            position = vector(field(water, "pos")), vertices = sequence(field(water, "vertices")),
            depths = sequence(field(water, "dephts")), indices = sequence(field(water, "indices")),
            contours = contourRows }
    end)
    coroutine.yield()
    summary.buildings = exportCategory("buildings", types.TOWN_BUILDING, function(entity)
        local building = component(entity, types.TOWN_BUILDING)
        local capacity = component(entity, types.PERSON_CAPACITY)
        return { id = entity, position = position(entity), town = field(building, "town"),
            personCapacity = field(building, "personCapacity"),
            capacityType = field(capacity, "type"), capacity = field(capacity, "capacity"),
            level = field(building, "level"), height = field(building, "height"),
            depth = field(building, "depth"), parcels = sequence(field(building, "parcels")),
            timeBuilt = field(building, "timeBuilt") }
    end)
    coroutine.yield()
    summary.parcels = exportCategory("parcels", types.PARCEL, function(entity)
        local parcel = component(entity, types.PARCEL)
        return { id = entity, streetSegment = field(parcel, "streetSegment"),
            left = field(parcel, "left"), curveParam = field(parcel, "curveParam"),
            offset = field(parcel, "offset"), faces = sequence(field(parcel, "faces")) }
    end)
    coroutine.yield()
    summary.emission = exportCategory("emission", types.EMISSION_GRID, function(entity)
        local grid = component(entity, types.EMISSION_GRID)
        return { id = entity, x0 = field(grid, "X0"), y0 = field(grid, "Y0"),
            height = field(grid, "height"), width = field(grid, "width"),
            gridPointSize = vector(field(grid, "gridPointSize")) }
    end)
    coroutine.yield()
    summary.persons = exportCategory("persons", types.SIM_PERSON, function(entity)
        local person = component(entity, types.SIM_PERSON)
        return { id = entity, destinations = sequence(field(person, "destinations")),
            moveModes = sequence(field(person, "moveModes")),
            travelTimes = sequence(field(person, "travelTimes")),
            targetOrAtEntity = field(person, "targetOrAtEntity"),
            lastMoveMode = field(person, "lastMoveMode"),
            lastDestinationUpdate = field(person, "lastDestinationUpdate") }
    end)
    coroutine.yield()
    summary.waiting_persons = exportCategory("waiting_persons", types.SIM_PERSON_AT_TERMINAL, function(entity)
        local waiting = component(entity, types.SIM_PERSON_AT_TERMINAL)
        return { id = entity, edgeId = field(waiting, "edgeId"), place = field(waiting, "place") }
    end)
    coroutine.yield()
    summary.riding_persons = exportCategory("riding_persons", types.SIM_PERSON_AT_VEHICLE, function(entity)
        local riding = component(entity, types.SIM_PERSON_AT_VEHICLE)
        return { id = entity, vehicle = field(riding, "vehicle"),
            part = field(riding, "part"), place = field(riding, "place") }
    end)
    coroutine.yield()
    local function writeSystemMapping(fileName, getter)
        local file = assert(io.open(outputRoot .. fileName .. ".jsonl", "wb"))
        local ok, values = pcall(getter)
        local count = 0
        if ok and values then
            for key, item in pairs(values) do
                file:write(encode({ key = tostring(key), values = mapping(item) }), "\n")
                count = count + 1
            end
        end
        file:close()
        return { count = count, errors = ok and 0 or 1 }
    end
    summary.terminal_line_stops = writeSystemMapping("terminal_line_stops", function()
        return api.engine.system.line.getTerminal2lineStops()
    end)
    coroutine.yield()
    summary.station_group_line_stops = writeSystemMapping("station_group_line_stops", function()
        return api.engine.system.line.getStationGroup2LineStopsMap()
    end)
    coroutine.yield()
    local file = assert(io.open(outputRoot .. "summary.json", "wb"))
    file:write(encode(summary), "\n")
    file:close()
end

function data()
    return {
        update = function()
            if finished then return end
            if not runner then runner = coroutine.create(export) end
            local ok, message = coroutine.resume(runner)
            if not ok then
                finished = true
                print("Save GIS Exporter: " .. tostring(message))
            elseif coroutine.status(runner) == "dead" then
                finished = true
            end
        end,
    }
end
