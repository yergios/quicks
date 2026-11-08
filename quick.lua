#!/usr/bin/env lua

-- Configuration
local AUTHOR = "Sergio Y. Lee"

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

-- Templates are read from the directory this script lives in, so a clone of
-- the repo works wherever it is placed.
local TEMPLATES = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."

-- New projects are created in QUICKS_DIR when set, otherwise in the current
-- directory. Set it per machine in the shell profile or system environment.
local OUTPUT = os.getenv("QUICKS_DIR")
if OUTPUT == "" then
  OUTPUT = nil
end

local function get_current_date()
  return os.date("%Y-%m-%d")
end

local function path_exists(path)
  local ok, err, code = os.rename(path, path)
  if not ok then
    if code == 13 then
      -- Permission denied, but it exists
      return true
    end
  end
  return ok, err
end

local function path_join(...)
  local parts = { ... }
  local separator = is_windows() and "\\" or "/"
  return table.concat(parts, separator)
end

local function escape_path(path)
  if is_windows() then
    return '"' .. (path:gsub('"', "")) .. '"'
  else
    -- Inside double quotes the shell still expands $ and backticks
    return '"' .. (path:gsub('[\\"$`]', "\\%0")) .. '"'
  end
end

-- Build output and installed dependencies live next to the templates while
-- they are being developed. They must not end up in new projects.
local EXCLUDE_DIRS = { "node_modules", "dist", ".astro", "build" }
local EXCLUDE_FILES = { "pnpm-lock.yaml" }

local function copy_directory(source, destination)
  if is_windows() then
    -- robocopy exits with 0-7 on success, 8 and above on failure
    local copy_cmd = "robocopy "
      .. escape_path(source)
      .. " "
      .. escape_path(destination)
      .. " /E /NFL /NDL /NJH /NJS /NP /XD "
      .. table.concat(EXCLUDE_DIRS, " ")
      .. " /XF "
      .. table.concat(EXCLUDE_FILES, " ")
    local _, _, exit_code = os.execute(copy_cmd)
    return exit_code ~= nil and exit_code < 8, exit_code
  end

  local excludes = {}
  for _, name in ipairs(EXCLUDE_DIRS) do
    excludes[#excludes + 1] = "--exclude=" .. name
  end
  for _, name in ipairs(EXCLUDE_FILES) do
    excludes[#excludes + 1] = "--exclude=" .. name
  end
  local copy_cmd = "mkdir -p "
    .. escape_path(destination)
    .. " && tar -C "
    .. escape_path(source)
    .. " "
    .. table.concat(excludes, " ")
    .. " -cf - . | tar -C "
    .. escape_path(destination)
    .. " -xf -"
  local result, _, exit_code = os.execute(copy_cmd)
  return result, exit_code
end

local function move_file(source, destination)
  local move_cmd
  if is_windows() then
    move_cmd = "move " .. escape_path(source) .. " " .. escape_path(destination)
  else
    move_cmd = "mv " .. escape_path(source) .. " " .. escape_path(destination)
  end

  local result, _, exit_code = os.execute(move_cmd)
  return result, exit_code
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "Could not open file: " .. path
  end

  local content = file:read("*all")
  file:close()
  return content
end

local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false, "Could not write to file: " .. path
  end

  file:write(content)
  file:close()
  return true
end

-- Plain text replace. A gsub replacement string would treat % in names as an
-- escape and raise an error.
local function replace_text(content, placeholder, value)
  return (content:gsub(placeholder, function()
    return value
  end))
end

local function update_file_content(file_path, program_name, file_name)
  local content, err = read_file(file_path)
  if not content then
    print("Warning: " .. err)
    return false
  end

  local current_date = get_current_date()

  content = replace_text(content, "{{FILENAME}}", file_name)
  content = replace_text(content, "{{AUTHOR}}", AUTHOR)
  content = replace_text(content, "{{DATE}}", current_date)
  content = replace_text(
    content,
    "{{DESCRIPTION}}",
    "Brief description of " .. program_name
  )

  local success, err = write_file(file_path, content)
  if not success then
    print("Warning: " .. err)
    return false
  end

  return true
end

local function update_tooling_files(program_name, target_dir)
  for _, name in ipairs({ "build.lua", "run.lua" }) do
    local path = path_join(target_dir, name)
    local content = read_file(path)
    if content then
      content = replace_text(
        content,
        'local PROJECT_NAME = "quick"',
        'local PROJECT_NAME = "' .. program_name .. '"'
      )
      write_file(path, content)
    end
  end
end

-- Where a new project directory goes: inside QUICKS_DIR if set, else the cwd.
local function get_target_dir(dir_name)
  if OUTPUT then
    return path_join(OUTPUT, dir_name)
  end
  return dir_name
end

-- Fails early with a clear message instead of a cryptic copy error.
local function check_output_dir()
  if OUTPUT and not path_exists(OUTPUT) then
    print("QUICKS_DIR does not exist: " .. OUTPUT)
    return false
  end
  return true
end

local function open_editor(file_path)
  if file_path and file_path ~= "" then
    local cmd = "nvim " .. escape_path(file_path)
    os.execute(cmd)
  else
    os.execute("nvim")
  end
end

local function to_kebab_case(str)
  local kebab = str:lower():gsub("[%s_]+", "-"):gsub("[^%a%d%-]", "")
  return kebab
end

local function set_package_name(target_dir, name)
  local path = path_join(target_dir, "package.json")
  local content = read_file(path)
  if content then
    content = content:gsub('"name": "[^"]*"', '"name": "' .. name .. '"', 1)
    write_file(path, content)
  end
end

local function create_astro_project(site_name)
  local kebab_name = to_kebab_case(site_name)
  local dir_name = get_target_dir(kebab_name)

  if path_exists(dir_name) then
    print("Directory '" .. dir_name .. "' already exists")
    return false
  end

  local template_dir = path_join(TEMPLATES, "astro")
  if not path_exists(template_dir) then
    print("Template directory not found: " .. template_dir)
    return false
  end

  local success, _ = copy_directory(template_dir, dir_name)
  if not success then
    print("Error copying template directory")
    return false
  end

  set_package_name(dir_name, kebab_name)

  local domain = site_name:lower():gsub("[^%a%d]", "") .. ".com"
  local description = "Welcome to " .. site_name .. "."

  local files_to_update = {
    path_join(dir_name, "astro.config.mjs"),
    path_join(dir_name, "src", "layouts", "Layout.astro"),
    path_join(dir_name, "src", "pages", "index.astro"),
  }

  for _, file_path in ipairs(files_to_update) do
    local content, err = read_file(file_path)
    if content then
      content = replace_text(content, "{{SITENAME}}", site_name)
      content = replace_text(content, "{{DOMAIN}}", domain)
      content = replace_text(content, "{{DESCRIPTION}}", description)
      content = replace_text(content, "{{OG_IMAGE}}", "/og.png")
      write_file(file_path, content)
    else
      print("Warning: " .. (err or "could not read " .. file_path))
    end
  end

  local main_file = path_join(dir_name, "src", "pages", "index.astro")
  open_editor(main_file)
  return true
end

local function create_csharp_project(program_name)
  local target_dir = get_target_dir(program_name)

  if path_exists(target_dir) then
    print("Directory '" .. target_dir .. "' already exists")
    return false
  end

  local dotnet_cmd = "dotnet new console -n "
    .. escape_path(program_name)
    .. " -o "
    .. escape_path(target_dir)
    .. " --use-program-main"
  local result, _, exit_code = os.execute(dotnet_cmd)

  if not result then
    print("Error creating C# project")
    return false
  end

  open_editor(path_join(target_dir, "Program.cs"))
  return true
end

local function process_c_cpp_template(program_name, language, target_dir)
  local extension = (language == "cpp") and ".cpp" or ".c"
  local main_file = ""

  -- Rename the source file
  local file_name = program_name .. extension
  local old_path = path_join(target_dir, "src", "quick.c")
  local new_path = path_join(target_dir, "src", file_name)

  if path_exists(old_path) then
    local success = move_file(old_path, new_path)
    if success then
      main_file = new_path
      update_file_content(main_file, program_name, file_name)
    else
      print("Error renaming source file")
    end
  end

  -- Update build files
  update_tooling_files(program_name, target_dir)

  return main_file
end

local USAGE = "Usage: lua quick.lua <language> <program_name>\n"
  .. "Supported languages: c, cpp, cs, ts, astro"

local function quick(language, program_name)
  if not language or not program_name then
    print(USAGE)
    return
  end

  language = language:lower()

  -- cs has no template directory, it is generated by dotnet
  local template_mapping = {
    c = "c",
    cpp = "c", -- cpp uses the same template as c
    ts = "ts",
    astro = "astro",
  }

  if language ~= "cs" and not template_mapping[language] then
    print("Unsupported language: " .. language)
    print(USAGE)
    return
  end

  if not check_output_dir() then
    return
  end

  -- Handle C# differently
  if language == "cs" then
    create_csharp_project(program_name)
    return
  end

  -- Handle Astro: program_name is treated as the site name
  if language == "astro" then
    create_astro_project(program_name)
    return
  end

  local target_dir = get_target_dir(program_name)

  -- Check if directory already exists
  if path_exists(target_dir) then
    print("Directory '" .. target_dir .. "' already exists")
    return
  end

  -- Copy template
  local template_dir = path_join(TEMPLATES, template_mapping[language])

  if not path_exists(template_dir) then
    print("Template directory not found: " .. template_dir)
    return
  end

  local success, exit_code = copy_directory(template_dir, target_dir)
  if not success then
    print("Error copying template directory")
    return
  end

  local main_file = ""

  -- Language-specific processing
  if language == "c" or language == "cpp" then
    main_file = process_c_cpp_template(program_name, language, target_dir)
  elseif language == "ts" then
    set_package_name(target_dir, to_kebab_case(program_name))
    main_file = path_join(target_dir, "index.ts")
  end

  open_editor(main_file)
end

-- Main execution
if arg and #arg >= 2 then
  quick(arg[1], arg[2])
else
  print(USAGE)
end
