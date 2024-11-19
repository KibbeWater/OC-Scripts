#REGION VARS
local RUNNING = "Reactor is active"
local EFF_OVER = "Cooling down, efficiency lowering"
local POW_LOW = "FATAL: CONTROLLER LOSING POWER"

local lastSwitchUptime = 0
local switchTime = 5
local lastEff = 0
#ENDREGION

#REGION RUN
local _heat = heat / maxHeat
local _power = power / maxPower
local _computerEnergy = computerEnergy / maxComputerEnergy
local _eff = efficiency

local isEffUp = false
if lastEff <= _eff then isEffUp = true end

if _computerEnergy <= computerPowerThreshold then
  controllerReason = POW_LOW
  stop()
  return
end

if lastSwitchUptime + switchTime > computer.uptime() then return end
if not isEffUp and isOn and _eff+reactorEffThreshold <= 100 then
  stop()
  controllerReason = EFF_OVER
  lastSwitchUptime = computer.uptime()
elseif not isEffUp and not isOn and _eff+reactorEffThreshold <= 100 then
  start()
  controllerReason = RUNNING
  lastSwitchUptime = computer.uptime()
end
lastEff = _eff
#ENDREGION