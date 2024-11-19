local component = require("component")
local serialization = require("serialization")
local event = require("event")
local m = component.modem

local _PORT = 22
local _PROTOCOL = "FTP"
if not m then
  io.stderr:write("Modem not installed")
  os.exit(1)
end

function waitForMessage(messageType, optFrom)
  while true do
    local _, _, from, port, _, protocol, message = event.pull("modem_message")
    if protocol ~= _PROTOCOL then goto continue end

    local packet = serialization.unserialize(message)
    if packet.type == messageType and (not optFrom or optFrom == from) then
      packet.meta = {from=from}
      return packet 
    end

    ::continue::
  end
end

function send(to, packet)
  m.send(to, _PORT, _PROTOCOL, serialization.serialize(packet))
end

m.open(_PORT)
print("Finding sender...")
m.broadcast(_PORT, _PROTOCOL, serialization.serialize(
  {
    type = "FIND"
  }
))
local clientHello = waitForMessage("HELLO")
print("Found sender")
local filename = clientHello.name
local sender = clientHello.meta.from
send(sender, {type="WAITING"})
print("Waiting for data")
local file = waitForMessage("FILE")

local stream = io.open(filename, "w")
stream:write(file.content)
stream:close()
print("Written file to " .. filename)

m.close(_PORT)