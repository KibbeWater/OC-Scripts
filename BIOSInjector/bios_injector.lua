local component = require("component")
local remapper = require("remapper")

if not remapper then
  io.stderr:write("Remapper library not installed")
  os.exit(1)
end

local injector = {}

function injector.inject(data, label)
  checkArg(1, data, "string")
  if label ~= nil then checkArg(2, label, "string") end

  local eeprom = component.eeprom
  if not eeprom then
    io.stderr:write("EEPROM not installed")
    os.exit(1)
  end

  local prevFirmware = remapper.minify(eeprom.get())
  local prevLabel = eeprom.getLabel()
 
  local payload = [[
    local eeprom = component.proxy(component.list("eeprom")())
    local firm = [[]] .. prevFirmware .. "]]" .. [[

    ]]..data..[[

    eeprom.setLabel([[]] .. prevLabel .. "]]" ..  [[)
    eeprom.set(firm)
    load(firm)()
  ]]

  local defLabel = prevLabel .. " (MOD)"

  eeprom.setLabel(label or defLabel)
  eeprom.set(remapper.minify(payload))
end

return injector