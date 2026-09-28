local outputRoot = os.getenv("USERPROFILE") .. "/VSC/transport-fever-2-save-analysis/export/"
local frame = 0
local interval = 120

local function field(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function encode(value)
    if value == nil then return "null" end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) == "string" then return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
    if type(value) ~= "table" then return '"' .. tostring(value) .. '"' end
    local parts = {}
    if #value > 0 then
        for i = 1, #value do parts[#parts + 1] = encode(value[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do parts[#parts + 1] = encode(tostring(key)) .. ":" .. encode(item) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function vector(value)
    if value == nil then return nil end
    return { field(value, "x") or field(value, 1), field(value, "y") or field(value, 2), field(value, "z") or field(value, 3) or 0 }
end

local function snapshot()
    local types = api.type.ComponentType
    local vehicles, waiting, riding = {}, 0, 0
    api.engine.forEachEntityWithComponent(function(entity)
        local vehicle = api.engine.getComponent(entity, types.TRANSPORT_VEHICLE)
        local old = game.interface.getEntity(entity)
        vehicles[#vehicles + 1] = { id = entity, line = field(vehicle, "line"), position = vector(field(old, "position")), stopIndex = field(vehicle, "stopIndex") }
    end, types.TRANSPORT_VEHICLE)
    api.engine.forEachEntityWithComponent(function() waiting = waiting + 1 end, types.SIM_PERSON_AT_TERMINAL)
    api.engine.forEachEntityWithComponent(function() riding = riding + 1 end, types.SIM_PERSON_AT_VEHICLE)
    local payload = { frame = frame, vehicles = vehicles, waiting = waiting, riding = riding }
    local file = assert(io.open(outputRoot .. "dynamic_snapshot.json", "wb"))
    file:write(encode(payload), "\n")
    file:close()
end

function data()
    return { update = function()
        frame = frame + 1
        if frame % interval == 0 then
            local ok, message = pcall(snapshot)
            if not ok then print("Dynamic snapshot: " .. tostring(message)) end
        end
    end }
end
