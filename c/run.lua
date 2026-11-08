#!/usr/bin/env lua

-- Configuration: Change this to your project name
local PROJECT_NAME = "quick"

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function parse_args()
  local config = "debug"
  local program_args = {}
  local i = 1

  if arg and arg[1] and arg[1]:lower() == "release" then
    config = "release"
    i = 2
  end

  while arg and arg[i] do
    program_args[#program_args + 1] = arg[i]
    i = i + 1
  end

  return config, program_args
end

local function get_executable_path(config)
  if is_windows() then
    return "build\\" .. config .. "\\" .. PROJECT_NAME .. ".exe"
  else
    return "build/" .. config .. "/" .. PROJECT_NAME
  end
end

local function path_exists(file)
  local ok, err, code = os.rename(file, file)
  if not ok then
    if code == 13 then
      -- Permission denied, but it exists
      return true
    end
  end
  return ok, err
end

local function escape_arg(arg)
  if is_windows() then
    if arg:find(" ") or arg:find('"') then
      return '"' .. arg:gsub('"', '""') .. '"'
    end
    return arg
  else
    return "'" .. arg:gsub("'", "'\"'\"'") .. "'"
  end
end

local function run_program(executable, args)
  if not path_exists(executable) then
    print("Error: Executable not found: " .. executable)
    return false
  end

  local cmd = escape_arg(executable)
  for _, arg in ipairs(args) do
    cmd = cmd .. " " .. escape_arg(arg)
  end

  local result, _, exit_code = os.execute(cmd)
  return result, exit_code
end

local function run()
  local config, program_args = parse_args()
  local executable = get_executable_path(config)
  local success, exit_code = run_program(executable, program_args)

  if not success then
    os.exit(exit_code or 1)
  end
end

run()
