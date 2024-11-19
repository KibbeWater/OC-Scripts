-- remapper.lua
local remapper = {}

-- Helper function to generate a short, unique name (e.g., f1, f2, f3, ...)
local function generateMinifiedName(index)
    return "f" .. index
end

-- Function to generate minified names for functions and return the modified Lua code
function remapper.remapFunctions(luaCode, functionNames)
    -- Create a remap table with generated minified names for each function
    local remapTable = {}
    local index = 1
    for _, funcName in ipairs(functionNames) do
        local newName = generateMinifiedName(index)  -- Generate a minified name like f1, f2, etc.
        remapTable[funcName] = newName
        index = index + 1
    end

    -- Loop through the remap table and replace function names in the Lua code
    for oldName, newName in pairs(remapTable) do
        luaCode = luaCode:gsub(oldName, newName)
    end

    -- Return the modified Lua code
    return luaCode
end

-- Function to minify Lua code by removing unnecessary whitespaces and newlines
function remapper.minify(luaCode)
    -- Remove single-line comments
    local minifiedCode = luaCode:gsub("%-%-[^\n]*", "")

    -- Remove multi-line comments
    minifiedCode = minifiedCode:gsub("%-%-%[(=*)%[.-%]%1%]", "")

    -- Trim leading and trailing whitespace
    minifiedCode = minifiedCode:gsub("^%s+", ""):gsub("%s+$", "")

    -- Replace multiple spaces with a single space
    minifiedCode = minifiedCode:gsub("%s+", " ")

    -- Replace spaces around special characters
    minifiedCode = minifiedCode:gsub("%s*([=,%(%)%{%}%[%];])%s*", "%1")

    -- Handle newlines for better compression (optional)
    minifiedCode = minifiedCode:gsub("\n+", " ")

    return minifiedCode
end

-- Return the module table
return remapper