local component = require("component")
local computer = require("computer")
local event = require("event")
local serialization = require("serialization")
local term = require("term")
local thread = require("thread")
local fs = require("filesystem")

local m = component.modem
local g = component.gpu

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
  print("10 = Iron Xylophone (Iron Block)")
  print("11 = Cow Bell (Soul Sand)")
  print("12 = Didgeridoo (Pumpkin)")
  print("13 = Bit (Block of Emerald)")
  print("14 = Banjo (Hay)")
  print("15 = Pling (Glowstone)")
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
      if input < 0 or input > 15 then
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

function hasPixelChange(progress, oldProgress, width)
    -- Calculate the pixel positions using integer math
    local newPixel = math.floor(progress * width + 0.5) -- Round to nearest pixel
    local oldPixel = math.floor(oldProgress * width + 0.5) -- Round to nearest pixel
    
    -- Check if there's a difference in pixel positions
    return newPixel ~= oldPixel
end

function render(prog, w, h)
  if not g then return end

  local f = g.getForeground()
  local b = g.getBackground()

  g.setBackground(0x000000)
  g.setForeground(0xFFFFFF)
  g.fill(1, h, w, h, " ")
  
  g.setBackground(0xFFFFFF)
  g.setForeground(0x000000)
  g.fill(1, h-1, w, h-1, " ")
  g.set(2, h-1, "Currently Playing: " .. (songMeta or {}).name .. " - " .. (songMeta or {}).author)

  g.setBackground(0x330000)
  g.fill(1, h, w*prog, h, " ")

  g.setForeground(f)
  g.setBackground(b)
end

function runSong(time)
  local idx = 1
  local lastPitch = {}

  local shouldRerender = true
  local prog = 0
  local lastRenderedProg = 0

  local w, h
  if g ~= nil then w, h = g.getResolution() end
  while true do
    local note = notes[idx]
    if not note then break end

    local noteblock = instruments[note.i]
    if not noteblock then 
      os.sleep(0) -- Prevent errors by not yielding
      goto continue 
    end

    if hasPixelChange(prog, lastRenderedProg, w) then shouldRerender = true end

    -- Is it time to play
    repeat
      if shouldRerender then
        prog = idx / #notes
        render(prog, w, h)
        lastRenderedProg = prog
        shouldRerender = false
      else os.sleep(0.01) end
    until time + note.t <= computer.uptime()

    noteblock.trigger(note.p)

    ::continue::
    idx = idx + 1
  end
  print("Finished playing")
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