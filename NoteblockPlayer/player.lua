local component = require("component")
local computer = require("computer")
local event = require("event")
local serialization = require("serialization")
local term = require("term")
local thread = require("thread")
local fs = require("filesystem")

local m = component.modem

local _PORT = 3001
local _PROTOCOL = "PLR1"

-- Global Vars
local masterAddr = ""
local songMeta = nil
local notes = nil
local instruments = {}

-- Utility Functions
function prepModem(mode)
  m.setWakeMessage(_PROTOCOL)
  if m.isOpen(_PORT) == not mode then 
    if mode then 
      m.open(_PORT) 
    else 
      m.close(_PORT) 
    end
  end
end

-- Functions
function printInstruments()
  print("0 = Piano (Air)")
  print("1 = Double Bass (Wood)")
  print("2 = Bass Drum (Stone)")
  print("3 = Snare Drum (Sand)")
  print("4 = Click (Glass)")
  print("5 = Guitar (Wool)")
  print("6 = Flute (Clay)")
  print("7 = Bell (Block of Gold)")
  print("8 = Chime (Packed Ice)")
  print("9 = Xylophone (Bone Block)")
end

function loadCalibration()
  local stream = io.open("calibration.dat")
  if not stream then return end
  local content = stream:read("*a")
  stream:close()

  local _instruments = serialization.unserialize(content)
  for k,v in pairs(_instruments) do
    instruments[k] = component.proxy(v)
  end
end

function calibrate()
  instruments = {}

  local instrumentSav = {}
  for address, componentType in component.list("note_block") do 
    printInstruments()
    local block = component.proxy(address)

    for i=1, 10 do
      block.trigger()
      os.sleep(0.5)
    end

    print("\nPlease pick instrument:")
    while true do
      local input = tonumber(term.read()) or -1
      if input < 0 or input > 9 then
        print("Invalid instrument")
        goto continue
      end
  
      instruments[input] = block
      instrumentSav[input] = address

      term.clear()
      print("Assigned to instrument " .. input)

      break
      ::continue::
    end
  end

  local stream = io.open("calibration.dat", "w")
  stream:write(serialization.serialize(instrumentSav))
  stream:close()

  print("Finished calibration")
end

function runSong(time)
  local idx = 1
  local lastPitch = {}
  while true do
    local note = notes[idx]
    if not note then break end

    local noteblock = instruments[note.i]
    if not noteblock then 
      os.sleep(0.01) -- Prevent errors by not yielding
      goto continue 
    end

    local cPitch = lastPitch[note.i]
    local dPitch = note.p
    if cPitch ~= dPitch then 
      lastPitch[note.i] = dPitch
      noteblock.setPitch(dPitch) 
    end
    
    -- Is it time to play
    repeat
      os.sleep(0.01)
    until time + note.t <= computer.uptime()

    noteblock.trigger()
    idx = idx + 1

    ::continue::
  end
  notes = nil
  songMeta = nil
end

function handleMessages(from, protocol, message)
  if protocol ~= _PROTOCOL then return end
  if masterAddr ~= "" and from ~= masterAddr then return end
  local packet = serialization.unserialize(message)

  if packet.type == "DISCOVER" and masterAddr == "" then
    masterAddr = from
    print("Found master")
    m.send(from, _PORT, _PROTOCOL, serialization.serialize(
      {
        type = "HELLO",
        instruments = instruments
      }
    ))
  elseif packet.type == "METADATA" and from == masterAddr then
    print("Received song metadata")
    songMeta = packet.metadata
  elseif packet.type == "NOTES" and from == masterAddr then
    print("Received notes payload")
    if notes == nil then notes = {} end
    for i=1, #packet.notes do
      table.insert(notes, packet.notes[i])
    end
    print("Finished processing notes")
  elseif packet.type == "PLAY" and from == masterAddr then
    if songMeta == nil then 
      print("We have no metadata, cannot play song")
    end
    
    print("Running song: " .. songMeta.name)
    runSong(computer.uptime())
    masterAddr = ""
  end
end

-- Run
prepModem(true)

loadCalibration()
local insLoaded = 0
for k,v in pairs(instruments) do insLoaded = insLoaded + 1 end
print("Loaded " .. insLoaded .. " instruments from disk")
if insLoaded == 0 then
  calibrate()
end

while true do
  local _, _, from, _, _, protocol, message = event.pull("modem_message")
  handleMessages(from, protocol, message)
end

prepModem(false)