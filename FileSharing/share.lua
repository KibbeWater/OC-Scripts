local shell = require("shell")
local fs = require("filesystem")
local event = require("event")
local component = require("component")
local serialization = require("serialization")
local m = component.modem

local args = shell.parse(...)
if #args == 0 then
  args = {"-"}
end

local input_method, input_param = "read", require("tty").getViewport()

local _PORT = 22
local _PROTOCOL = "FTP"
if not m then
  io.stderr:write("Missing modem module")
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

for i = 1, #args do
  local arg = shell.resolve(args[i])
  if fs.isDirectory(arg) then
    io.stderr:write(string.format('length %s: Is a directory\n', arg))
    os.exit(1)
  else
    local file, reason
    if args[i] == "-" then
      file, reason = io.stdin, "missing stdin"
      input_method, input_param = "readLine", false
    else
      file, reason = fs.open(arg)
    end
    if not file then
      io.stderr:write(string.format("lengtth: %s: %s\n", args[i], tostring(reason)))
      os.exit(1)
    else
      file:close()
      file = io.open(arg)
      local content = file:read("*a")
      
      print("Waiting for receiver...")
      m.open(_PORT)
      local find = waitForMessage("FIND")
      local receiver = find.meta.from
      print("Found receiver")
      send(receiver, {type="HELLO",name=fs.name(arg)})
      waitForMessage("WAITING")
      print("Sending file...")
      send(receiver, {type="FILE",content=content})
      m.close(_PORT)

      print("Finished sending")

      file:close()
    end
  end
end