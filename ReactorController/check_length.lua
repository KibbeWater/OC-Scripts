local shell = require("shell")
local io = require("io")

local dir = shell.getWorkingDirectory()
local fileDir = dir.."/bin/bios_fission.lua"
print(fileDir)

local file = io.open(fileDir)
local dat = file:read("*a")
print("Size: " .. string.len(dat))
file:close()