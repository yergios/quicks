#!/usr/bin/env lua

local build_config = arg and arg[1] or "debug"

-- Configuration: Change this to your project name
local PROJECT_NAME = "quick"

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function escape_path(path)
  if is_windows() then
    return '"' .. path:gsub('"', "") .. '"'
  else
    return '"' .. path:gsub('"', '\\"') .. '"'
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

local function create_dir(path)
  if path_exists(path) then
    return true
  end

  local mkdir_cmd
  if is_windows() then
    mkdir_cmd = "mkdir " .. escape_path(path)
  else
    mkdir_cmd = "mkdir -p " .. escape_path(path)
  end

  local ok, _, code = os.execute(mkdir_cmd)
  return ok, code
end

local function get_outdir()
  if build_config == "release" then
    return "build/release"
  else
    return "build/debug"
  end
end

local function find_source_files()
  local sources = {}
  local extensions = { "*.c", "*.cpp" }

  for _, ext in ipairs(extensions) do
    local find_cmd
    if is_windows() then
      find_cmd = "dir /b /s src\\" .. ext .. " 2>nul"
    else
      find_cmd = 'find src -name "' .. ext .. '" 2>/dev/null'
    end

    local handle = io.popen(find_cmd)
    if handle then
      for line in handle:lines() do
        if line and line ~= "" then
          sources[#sources + 1] = line:gsub("\\", "/")
        end
      end
      handle:close()
    end
  end

  return sources
end

local function get_compiler()
  -- ">nul" on Linux would create a file named "nul" instead of discarding
  local null_device = is_windows() and "nul" or "/dev/null"
  local cl_check = is_windows()
    and os.execute("cl >" .. null_device .. " 2>&1")
  local gcc_check = os.execute("gcc --version >" .. null_device .. " 2>&1")

  if cl_check then
    return "cl"
  elseif gcc_check then
    return "gcc"
  else
    print("No suitable compiler found (tried cl and gcc)")
    os.exit(1)
  end
end

local function get_compiler_flags(compiler)
  if compiler == "cl" then
    if build_config == "release" then
      return "/O2 /nologo"
    else
      return "/Zi /FS /Od /nologo"
    end
  else
    if build_config == "release" then
      return "-Wall -Wextra -Wshadow -pedantic -std=c99 -O2 -DNDEBUG"
    else
      return "-Wall -Wextra -Wshadow -pedantic -std=c99 -g -fsanitize=address -DDEBUG"
    end
  end
end

local function get_includes(compiler)
  if compiler == "cl" then
    return '/I"include" /I"vendor\\syl"'
  else
    return '-I"include" -I"vendor/syl"'
  end
end

local function get_output_flags(outdir, exe_name, compiler)
  if compiler == "cl" then
    return string.format(
      "/Fe%s\\%s.exe /Fo%s\\ /Fd%s\\",
      outdir,
      exe_name,
      outdir,
      outdir
    )
  else
    return string.format("-o %s/%s", outdir, exe_name)
  end
end

local function build()
  local outdir = get_outdir()
  local compiler = get_compiler()
  local flags = get_compiler_flags(compiler)
  local includes = get_includes(compiler)
  local sources = find_source_files()

  if #sources == 0 then
    print("No source files found in src directory")
    return false
  end

  local ok, code = create_dir(outdir)
  if not ok then
    print("Failed to create output directory: " .. outdir)
    return false
  end

  local exe_name = PROJECT_NAME
  local output_flags = get_output_flags(outdir, exe_name, compiler)
  local sources_str = table.concat(sources, " ")

  local compile_cmd
  if compiler == "cl" then
    compile_cmd = string.format(
      "%s %s %s %s %s",
      compiler,
      flags,
      includes,
      output_flags,
      sources_str
    )
  else
    compile_cmd = string.format(
      "%s %s %s %s %s",
      compiler,
      flags,
      includes,
      sources_str,
      output_flags
    )
  end

  return os.execute(compile_cmd)
end

if not build() then
  os.exit(1)
end
