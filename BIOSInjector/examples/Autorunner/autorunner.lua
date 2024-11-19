local bios_injector = require("bios_injector")

if not bios_injector then
  io.stderr:write("Bios Injector not installed")
  os.exit(1)
end

local payload = [[

function sleep(timeout)
  checkArg(1, timeout, "number", "nil")
  local deadline = computer.uptime() + (timeout or 0)
  repeat
    computer.pullSignal(deadline - computer.uptime())
  until computer.uptime() >= deadline
end

local internet = {}
function internet.request(url, data, headers, method)
    checkArg(1, url, "string")
    checkArg(2, data, "string", "table", "nil")
    checkArg(3, headers, "table", "nil")
    checkArg(4, method, "string", "nil")

    local inet = component.list("internet")()
    if not inet then
        return nil
    end
    inet = component.proxy(inet)

    local post
    if type(data) == "string" then
        post = data
    elseif type(data) == "table" then
        for k, v in pairs(data) do
            post = post and (post .. "&") or ""
            post = post .. tostring(k) .. "=" .. tostring(v)
        end
    end

    local request, reason = inet.request(url, post, headers, method)
    if not request then
        return nil
    end

    return setmetatable(
        {
            ["()"] = "function():string # Tries to read data from the socket stream and return the read byte array.",
            close = setmetatable(
                {},
                {
                    __call = request.close,
                    __tostring = function()
                        return "function() # closes the connection"
                    end
                }
            )
        },
        {
            __call = function()
                while true do
                    local data, reason = request.read()
                    if not data then
                        request.close()
                        if reason then
                            error(reason, 2)
                        else
                            return nil
                        end
                    elseif #data > 0 then
                        return data
                    end
                    sleep(0)
                end
            end,
            __index = request
        }
    )
end

local bootAddr
for address in component.list("filesystem") do
  _fs = component.proxy(address)
  if not _fs then goto continue end

  if _fs.exists("/init.lua") then
    bootAddr = address
    break
  end
  ::continue::
end
if not bootAddr then return end

local fs = component.proxy(bootAddr)
if not fs then return end

local handle = internet.request("https://raw.githubusercontent.com/KibbeWater/OC-Scripts/refs/heads/main/FileSharing/receive.lua")
local result = ""
for chunk in handle do result = result..chunk end

local filename = "_autorunBios"
local handle = fs.open("/home/"..filename..".lua", "w")
fs.write(handle, result)
fs.close(handle)

handle = fs.open("/home/.shrc", "w")
fs.seek(handle, "end", 0)
fs.write(handle, "\n"..filename.."\nrm /home/"..filename..".lua")
fs.close(handle)

]]

bios_injector.inject(payload, "Receiver Installer")