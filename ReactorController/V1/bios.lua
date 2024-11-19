-- Configuration
local FPS = 1 / 10
local PORT = 3000
local IS_DEBUGGING = true
local REACTOR_PROTOCOL = "RCT1"

local reactorEnableThreshold = 0.4
local reactorDisableThreshold = 0.9
local reactorHotThreshold = 0.1
local computerPowerThreshold = 0.3

-- Require Components
local reactor = component.proxy(component.list("nc_fission_reactor")())
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
function unserialize(a)local b=load("return "..a)if b then return b()else error("Failed to unserialize string")end end

-- Util Functions
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
  return "fission"
end

-- Controller Variables
local heat = 0
local maxHeat = 0
local power = 0
local maxPower = 0
local processTime = 0
local maxProcessTime = 0
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

function stop()
  if isOn then reactor.deactivate() end
end
function start()
  if not isOn then reactor.activate() end
end

function update()
  heat = reactor.getHeatLevel()
  maxHeat = reactor.getMaxHeatLevel()
  power = reactor.getEnergyStored()
  maxPower = reactor.getMaxEnergyStored()
  processTime = reactor.getCurrentProcessTime()
  maxProcessTime = reactor.getReactorProcessTime()
  isOn = reactor.isProcessing()

  computerEnergy = computer.energy()
  maxComputerEnergy = computer.maxEnergy()
end

local TOO_HOT = "Reactor too hot, not active"
local RUNNING = "Reactor is active"
local BUF_FULL = "Power buffer is full, waiting"
local POW_LOW = "Computer power is low, pausing"
function run()
  local _heat = heat / maxHeat
  local _power = power / maxPower
  local _computerEnergy = computerEnergy / maxComputerEnergy

  if _computerEnergy <= computerPowerThreshold then
    controllerReason = POW_LOW
    stop()
    return
  end

  if _heat >= reactorHotThreshold then
    controllerReason = TOO_HOT
    stop()
    return
  end

  if _power <= reactorEnableThreshold then
    controllerReason = RUNNING
    start()
  elseif _power >= reactorDisableThreshold then
    controllerReason = BUF_FULL
    stop()
  end
end

-- Pre-exec phase
stop()
initModem()

-- Event loop
while true do
  update()
  run()

  transmitReactorState()
  transmitControllerState()
  sleep(FPS)
end

deinitModem()