local shell = require("shell")
local io = require("io")
local filesystem = require("filesystem")
local minifier = require("remapper")

local firmPrefix = "bios"

-- Util

function getArchName(arch)
  return firmPrefix .. "_" .. arch
end

function join(arr, sep)
  local buf = ""  
  for i=1, #arr do
    if buf == "" then
      buf = arr[i]
    else
      buf = buf .. sep .. arr[i]
    end
  end
  return buf
end

function split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

function loadRemaps()
  local cwd = shell.getWorkingDirectory()
  local remapDir = cwd .. "/remap.dat"
  if not filesystem.exists(remapDir) then return {} end
  local stream = io.open(remapDir)

  local content = stream:read("*a")
  stream:close()
  
  return split(content, "\n")
end

-- Vars

local arches = {"fission", "fusion"}
local firmware = getArchName("base")

-- Execution

local loadedArch = {}
local loadedFirm = {}
local cwd = shell.getWorkingDirectory()

if not filesystem.exists(cwd .. "/bin") then filesystem.makeDirectory(cwd .. "/bin") end

for i=1, #arches do
  local curArch = arches[i]
  local archDir = cwd .. "/" .. getArchName(curArch) .. ".lua"
  
  if not filesystem.exists(archDir) then
    print("Arch " .. curArch .. " does not exist, skipping...")
    goto CONTINUE
  end
  print("Loading firm for " .. curArch .. "...")
  table.insert(loadedArch, curArch)
  loadedFirm[curArch] = {}

  local stream = io.open(archDir)
  isReadingRegion = false
  regionName = ""
  buffer = ""
  while true do
    local data = stream:read("*l")
    if data == nil then break end

    if data:match("#REGION%s+(%w+)") then
        -- Extract region name
        regionName = data:match("#REGION%s+(%w+)")
        isReadingRegion = true
        buffer = ""  -- Clear buffer for new region
        print("Found REGION: " .. regionName)
    elseif data:match("#ENDREGION") then
        if isReadingRegion then
            isReadingRegion = false
            loadedFirm[curArch][regionName] = buffer
            print("Loaded firmware for " .. regionName .. " on the " .. curArch .. " platform")
        else
          print("Ended un-opened region, invalid formatting")
        end
    elseif isReadingRegion then
        -- Append line to buffer if we are within a region
        buffer = buffer .. data .. "\n"
    end
  end
  stream:close()

  ::CONTINUE::
end

print("Successfully loaded firmware for: " .. join(loadedArch, ", "))

for i=1, #loadedArch do
  local curArch = loadedArch[i]
  local archDir = cwd .. "/bin/" .. getArchName(curArch) .. ".lua"
  if not filesystem.exists(archDir) then goto continue end

  if not filesystem.remove(archDir) then
    print("Unable to clear old firmware of " .. curArch)
  end

  ::continue::
end

print("Cleared old firmware")

local firmwareDir = cwd .. "/" .. firmware .. ".lua"

local firmStream = io.open(firmwareDir)

local remaps = loadRemaps()
for i=1, #loadedArch do
  local curArch = loadedArch[i]
  local archDir = cwd .. "/bin/" .. getArchName(curArch) .. ".lua"
  local buf = ""
  local stream = io.open(archDir, "w")

  while true do
    local line = firmStream:read("*l")
    if line == nil then break end

    if line:match("#DEFINE%s+(%w+)") then
      -- Extract region name
      local regionName = line:match("#DEFINE%s+(%w+)")
      print("Writing region " .. regionName .. " for " .. curArch)
      local firm = loadedFirm[curArch][regionName]
      if firm == nil then 
        print("WARN: Unable to find definition '" .. regionName .. "' for platform " .. curArch .. ". This may cause corrupted code")
        goto continue
      end

      buf = buf .. firm

      ::continue::
    else
      buf = buf .. line .. "\n"
    end
  end

  print("Finished writing " .. curArch .. ", minifying")
  --local minified, _ = minifier.parseAndMinify(buf)
  local minified = minifier.minify(minifier.remapFunctions(buf, remaps)) 
  --local minified = minifier.remapFunctions(buf, remaps) 
  stream:write(minified)

  print("Wrote fimware for " .. curArch)
  firmStream:seek("set")
end

print("Completed")