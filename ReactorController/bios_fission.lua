#REGION VARS
local TOO_HOT = "Reactor too hot, not active"
local RUNNING = "Reactor is active"
local BUF_FULL = "Power buffer is full, waiting"
local POW_LOW = "Computer power is low, pausing"
#ENDREGION

#REGION RUN
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
#ENDREGION