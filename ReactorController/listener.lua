local component = require("component")
local m = component.modem
local event = require("event")
local keyboard = require("keyboard")

local PROTOCOL = "RCT1"

if not m.isOpen(3000) then 
  m.open(3000) 
  print("Opened port 3000")
end

print("Starting listener")

function serialize(a)local b=""local c=type(a)if c=="number"then b=b..a elseif c=="boolean"then b=b..tostring(a)elseif c=="string"then b=b..string.format("%q",a)elseif c=="table"then b=b.."{"for d,e in pairs(a)do b=b.."["..serialize(d).."]="..serialize(e)..","end;b=b.."}"else error("cannot serialize a "..c)end;return b end
function unserialize(a)local b=load("return "..a)if b then return b()else error("Failed to unserialize string")end end

function parseMessage(msg)
  print(msg)
  local _msgProtocol = string.sub(msg, 0, string.len(PROTOCOL))
  local _msgData = string.sub(msg, string.len(PROTOCOL)+1)
  
  if PROTOCOL ~= _msgProtocol then 
    print("Invalid protocol: " .. _msgProtocol)
    return
  end

  local data = unserialize(_msgData)
 
  local t = data.type

  print(_msgData)
  if t == "REACTOR_STATE" then
    print("Heat: " .. data.heat)
    print("Energy: " .. data.power)
    print("Is Enabled: " .. tostring(data.isOn))
  elseif t == "CONTROLLER_STATE" then
    print("Computer Power: " .. data.power)
    print("Reason: " .. data.reason)
  end
end

while true do
  local _, _, from, port, _, message = event.pull("modem_message")
  -- print("Got a message from " .. from .. " on port " .. port .. ": " .. tostring(message))
  parseMessage(tostring(message))
  if keyboard.isShiftDown() then break end
  os.sleep(0.1)
end