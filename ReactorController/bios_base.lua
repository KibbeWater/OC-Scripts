-- Configuration
local FPS = 1 / 10
local PORT = 3000
local REACTOR_PROTOCOL = "RCT1"
local REACTOR_REG_PROTOCOL = "RRP1"
local TRANSMIT_FREQ = 0.5

local reactorEnableThreshold = 0.4
local reactorDisableThreshold = 0.9
local reactorHotThreshold = 0.1
local reactorEffThreshold = 1
local computerPowerThreshold = 0.3

-- Require Components
local reactor = {}
local m = component.proxy(component.list("modem")())

-- OS Functions
function sleep(timeout)
  checkArg(1, timeout, "number", "nil")
  local deadline = computer.uptime() + (timeout or 0)
  repeat
    computer.pullSignal(deadline - computer.uptime())
  until computer.uptime() >= deadline
end

-- Minified Serializer
function serialize(a)local b=""local c=type(a)if c=="number"then b=b..a elseif c=="boolean"then b=b..tostring(a)elseif c=="string"then b=b..string.format("%q",a)elseif c=="table"then b=b.."{"for d,e in pairs(a)do b=b.."["..serialize(d).."]="..serialize(e)..","end;b=b.."}"else error("cannot serialize a "..c)end;return b end

-- Util Functions
function register(from)
  
end

function broadcast(packet)
  local data = serialize(packet)
  m.broadcast(PORT, REACTOR_PROTOCOL .. data)
end

function initModem()
  if not m.isOpen(PORT) then
    m.open(PORT)
  end
end

function deinitModem()
  if m.isOpen(PORT) then
    m.close(PORT)
  end
end

function getReactorType()
  local fission = component.list("nc_fission_reactor")()
  local fusion  = component.list("nc_fusion_reactor")()
  if fusion ~= nil then 
    reactor = component.proxy(fusion)
    return "fusion" 
  end
  if fission ~= nil then
    reactor = component.proxy(fission)
    return "fission" 
  end
  return nil
end

-- Controller Variables
local heat = 0
local maxHeat = 0
local power = 0
local maxPower = 0
local processTime = 0
local maxProcessTime = 0
local efficiency = 100
local isOn = false

local computerEnergy = 0
local maxComputerEnergy = 0

local controllerReason = "Intermission"
local controllerType = getReactorType()

-- Reactor Functions
function transmitReactorState()
  local t = maxProcessTime
  if maxProcessTime == 0 then t = 1 end
  local packet = {
    type = "REACTOR_STATE",
    heat = heat / maxHeat,
    power = power / maxPower,
    time = processTime / t,
    efficiency = efficiency,
    isOn = isOn
  }
  broadcast(packet)
end

function transmitControllerState()
  local reactorType = controllerType
  if not reactorType then reactorType = "none" end
  local packet = {
    type = "CONTROLLER_STATE",
    reason = controllerReason,
    power = computerEnergy / maxComputerEnergy,
    reactorType = reactorType
  }
  broadcast(packet)
end

-- Reactor Util Functions

function stop()
  if isOn then reactor.deactivate() end
end
function start()
  if not isOn then reactor.activate() end
end

function getTemp() if controllerType == "fission" then return reactor.getHeatLevel() else return reactor.getTemperature() end end
function getMaxTemp() if controllerType == "fission" then return reactor.getMaxHeatLevel() else return reactor.getMaxTemperature() end end

function getPower() return reactor.getEnergyStored() end
function getMaxPower() return reactor.getMaxEnergyStored() end

function getTime() return reactor.getCurrentProcessTime() end
function getMaxTime() return reactor.getReactorProcessTime() end

function getREfficiency() if controllerType == "fission" then return 100 else return reactor.getEfficiency() end end

function getIsOn() return reactor.isProcessing() end

-- Function runtime

function update()
  heat = getTemp()
  maxHeat = getMaxTemp()
  power = getPower()
  maxPower = getMaxPower()
  processTime = getTime()
  maxProcessTime = getMaxTime()
  isOn = getIsOn()
  efficiency = getREfficiency()

  computerEnergy = computer.energy()
  maxComputerEnergy = computer.maxEnergy()
end

#DEFINE VARS
function run()
#DEFINE RUN
end

-- Pre-exec phase
stop()
initModem()

-- Event loop
local lastTrans = 0
while true do
  update()
  run()

  if lastTrans + TRANSMIT_FREQ < computer.uptime() then
    transmitReactorState()
    transmitControllerState()
    lastTrans = computer.uptime()
  end
  sleep(FPS)
end

deinitModem()