local component = require("component")
local note = require("note")
local serialization = require("serialization")
local computer = require("computer")
local event = require("event")
local term = require("term")
local fs = require("filesystem")
local inet = require("internet")

local m = component.modem

function prompt(text)
  checkArg(1, text, "string")

  print(text)
  local _in = term.read()
  return _in
end

local swapPath = "/tmp/nbs_swap-"
if fs.exists("/swap") then swapPath = "/swap/nbs_swap-" end

local selection = prompt("Select file option:\n1) Song from URL\n2) File from Disk")
local selNumber = tonumber(selection)
if not selNumber or selNumber < 1 or selNumber > 2 then
  io.stderr:write("Invalid selection")
  os.exit(1)
end
term.clear()

function math.clamp(x, min, max)
    if x < min then return min end
    if x > max then return max end
    return x
end

-- URL parsing functions
function transformGoogleDriveUrl(url)
    -- Match the Google Drive URL structure
    local drivePattern = "https://drive%.google%.com/file/d/([%w%-_]+)/view%?usp=drive_link"
    local fileId = url:match(drivePattern)
    
    -- If the URL matches, transform it to the desired format
    if fileId then
        return string.format("https://drive.usercontent.google.com/u/0/uc?id=%s&export=download", fileId)
    else
        -- Return the original URL if it's not a matching Google Drive URL
        return url
    end
end

local filePath
if selNumber == 1 then
  if not component.isAvailable("internet") then
    io.stderr:write("Unable to download from URL, no internet module installed")
    os.exit(1)
  end
  local url = prompt("Please provide a URL:")
  
  local tmpStream, reason = io.open("/tmp/song.nbs", "wb")
  if not tmpStream then
    io.stderr:write("Unable to open file for writing: " .. reason)
    os.exit(1)
  end

  url = transformGoogleDriveUrl(url)

  print("Downloading file...")
  local handle = inet.request(url)
  for _chunk in handle do 
    tmpStream:write(_chunk)
  end

  local mt = getmetatable(handle)
  local code, message, headers = mt.__index.response()

  print("Finished downloading, status code: " .. code)
  if code ~= 200 then
    io.stderr:write("Failed to download: " .. message)
    os.exit(1)
  end
  tmpStream:close()
  filePath = "/tmp/song.nbs"
elseif selNumber == 2 then
  filePath = prompt("Please provide a path:"):gsub("\n", "")
else
  io.stderr:write("Invalid selection")
  os.exit(1)
end

if not fs.exists(filePath) then
  io.stderr:write("File \"" .. filePath .. "\" does not exist")
  os.exit(1)
end

local buf = io.open(filePath, "rb")
print("Loaded song, parsing data...")

-- Constants
local _PORT = 3001
local _PROTOCOL = "PLR1"

-- Utility Functions
function buf:Skip(n)
  for i=1, n do self:ReadByte() end
end

function buf:ReadByte()
  return string.byte(self:read(1))
end

function buf:ReadShort()
  local b1 = self:ReadByte()
  local b2 = self:ReadByte()

  if not b2 then return 0 end
  local n = b2*256 + b1
  return n
end

function buf:ReadInt()
  local b1 = self:ReadByte()
  local b2 = self:ReadByte()
  local b3 = self:ReadByte()
  local b4 = self:ReadByte()

  if not b4 then return 0 end
  local n = b4*16777216 + b3*65536 + b2*256 + b1
  n = (n > 2147483647) and (n - 4294967296) or n
  return n
end

function buf:ReadIntString()
  local len = self:ReadInt()
  local out = ""
  if len == 0 then return "" end
  for i=1, len do
    out = out .. string.char(self:ReadByte())
  end
  return out
end

buf:seek("set")
buf:Skip(2)

local h_iVer = buf:ReadByte()
if h_iVer ~= 5 then
  io.stderr:write("Incompatible NBS version " .. h_iVer)
  os.exit(1)
end
local h_iInstrumentCount = buf:ReadByte()

local h_iSongLength = buf:ReadShort()
buf:Skip(2)
local h_sSongName = buf:ReadIntString()
print("Loading " .. h_sSongName .. "...")
local h_sSongAuthor = buf:ReadIntString()
print("MIDI song created by " .. h_sSongAuthor)
local h_sSongOrigAuthor = buf:ReadIntString()
print("Song created by " .. h_sSongOrigAuthor)
local h_sSongDesc = buf:ReadIntString()
print("\n"..h_sSongDesc.."\n")

local h_iTempo = (buf:ReadShort())/100
buf:Skip(2)
local h_iTimeSig = buf:ReadByte()
buf:Skip(20)
buf:ReadIntString()

buf:Skip(4)

local notes = {}
local players = {}

local swapCount = 1
local swapFile, reason = io.open(swapPath .. swapCount, "w")
if not swapFile then io.stderr:write("Error opening swap file: " .. reason) end

local tickCounter = 0
local noteCount = 0
while true do
  local tickToNext = buf:ReadShort()
  if tickToNext == 0 then break end

  noteCount = noteCount + 1
  tickCounter = tickCounter + tickToNext
  local t = (tickCounter / h_iTempo) / 1
  while true do
    local tickToJump = buf:ReadShort()
    if tickToJump == 0 then break end
    local _note = {}
    _note.i = buf:ReadByte() -- Instrument
    local pitch = buf:ReadByte()-33
    pitch = math.clamp(pitch, 1, 24)
    _note.p = pitch --note.ticks(buf:ReadByte()+34) -- Pitch
    _note.t = t
    table.insert(notes, _note)
    buf:Skip(4)

    if #notes%1000 == 0 then
      os.sleep(0.01)

      local s = serialization.serialize(notes)
      swapFile:write(s)
      swapFile:close()
      notes = {}
      swapCount = swapCount + 1
      swapFile, reason = io.open(swapPath .. swapCount, "w")
      if not swapFile then io.stderr:write("Error opening swap file: " .. reason) end
      print("Wrote to swap " .. (swapCount - 1))
    end    
  end
end

local sc = serialization.serialize(notes)
swapFile:write(sc)
swapFile:close()
notes = {}

print("Finished loading song into memory, note count: " .. noteCount)

function handleMessage(from, protocol, message)
  if protocol ~= _PROTOCOL then return end

  local packet = serialization.unserialize(message)
  if packet.type == "HELLO" then
    local player = {addr = from, instruments = packet.instruments}
    table.insert(players, player)
    print("Discovered new player: " .. from)
  end
end

print("Loaded song, discovering players...")
m.open(_PORT)
local deadline = computer.uptime() + 5
repeat
  m.broadcast(_PORT, _PROTOCOL, serialization.serialize(
    {
      type = "DISCOVER"
    }
  ))
  local _, _, from, port, _, protocol, message = event.pull(0.5, "modem_message")
  handleMessage(from, protocol, message)
until deadline <= computer.uptime()

if #players == 0 then
  io.stderr:write("No players found")
  os.exit(1)
end
print("Found " .. #players .. " players")

for i=1, #players do
  local player = players[i]
  if not player then break end

  m.send(player.addr, _PORT, _PROTOCOL, serialization.serialize(
    {
      type = "METADATA",
      metadata = {
        name = h_sSongName,
        author = h_sSongAuthor,
        description = h_sSongDesc
      }
    }
  ))
end

local playerNotes = {}
local lastTime = 0
local plrIdx = 1

function nextPlayer()
  if plrIdx + 1 > #players then 
    plrIdx = 1 
  else
    plrIdx = plrIdx + 1
  end
  return plrIdx
end

for i=1, #players do playerNotes[players[i].addr] = {} end

for y=1, swapCount do
  local handle = io.open(swapPath..y, "r")
  local content = handle:read("*a")
  notes = serialization.unserialize(content) or {}
  content = ""
  handle:close()

  print("Reading swap " .. y .. " of size " .. #notes)

  for i=1, #notes do
    local note = notes[i]
    local plr
    if note.t <= lastTime+0.1 then plr = players[nextPlayer()] else plr = players[plrIdx] end
    if not plr then break end

    table.insert(playerNotes[plr.addr], note)
    lastTime=note.t
  end

  for addr,n in pairs(playerNotes) do
    local chunks = {}
    local chunkSize = 20

    local idx = 1
    local max = #n
    local nBuf = {}
    while true do
      if idx > max then 
        table.insert(chunks, nBuf) 
        break
      end

      table.insert(nBuf, n[idx])
    
      if idx%chunkSize == 0 then
        table.insert(chunks, nBuf)
        nBuf = {}
      end
      idx = idx + 1
    end

    for i=1, #chunks do
      m.send(addr, _PORT, _PROTOCOL, serialization.serialize(
        {type="NOTES",notes=chunks[i]}
      ))
    end
  end

  -- Clear memory
  for k in pairs(playerNotes) do
    playerNotes[k] = {}
  end  
end

print("Sent all payloads, playing in 3s")
os.sleep(3)

m.broadcast(_PORT, _PROTOCOL, serialization.serialize(
  {
    type = "PLAY"
  }
))

m.close(_PORT)