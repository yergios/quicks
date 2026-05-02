#!/usr/bin/env lua

-- Configuration
local REPOS = package.config:sub(1, 1) == "\\" and "D:\\repos" or "/mnt/shared/repos"
local AUTHOR = "Sergio Y. Lee"

function is_windows()
  return package.config:sub(1, 1) == "\\"
end

function get_current_date()
  return os.date("%Y-%m-%d")
end

function path_exists(path)
  local ok, err, code = os.rename(path, path)
  if not ok then
    if code == 13 then
      -- Permission denied, but it exists
      return true
    end
  end
  return ok, err
end

function path_join(...)
  local parts = { ... }
  local separator = is_windows() and "\\" or "/"
  return table.concat(parts, separator)
end

function escape_path(path)
  if is_windows() then
    return '"' .. path:gsub('"', "") .. '"'
  else
    return '"' .. path:gsub('"', '\\"') .. '"'
  end
end

function copy_directory(source, destination)
  local copy_cmd
  if is_windows() then
    copy_cmd = "xcopy "
      .. escape_path(source)
      .. " "
      .. escape_path(destination)
      .. " /E /I /Y"
  else
    copy_cmd = "cp -r "
      .. escape_path(source)
      .. " "
      .. escape_path(destination)
  end

  local result, _, exit_code = os.execute(copy_cmd)
  return result, exit_code
end

function move_file(source, destination)
  local move_cmd
  if is_windows() then
    move_cmd = "move " .. escape_path(source) .. " " .. escape_path(destination)
  else
    move_cmd = "mv " .. escape_path(source) .. " " .. escape_path(destination)
  end

  local result, _, exit_code = os.execute(move_cmd)
  return result, exit_code
end

function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "Could not open file: " .. path
  end

  local content = file:read("*all")
  file:close()
  return content
end

function write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false, "Could not write to file: " .. path
  end

  file:write(content)
  file:close()
  return true
end

function update_file_content(file_path, program_name)
  local content, err = read_file(file_path)
  if not content then
    print("Warning: " .. err)
    return false
  end

  local current_date = get_current_date()

  content = content:gsub("{{FILENAME}}", program_name .. ".c")
  content = content:gsub("{{AUTHOR}}", AUTHOR)
  content = content:gsub("{{DATE}}", current_date)
  content =
    content:gsub("{{DESCRIPTION}}", "Brief description of " .. program_name)

  local success, err = write_file(file_path, content)
  if not success then
    print("Warning: " .. err)
    return false
  end

  return true
end

function update_tooling_files(program_name, language)
  -- Update build.lua if it exists
  if path_exists("build.lua") then
    local content, err = read_file("build.lua")
    if content then
      content = content:gsub(
        'local PROJECT_NAME = "quick"',
        'local PROJECT_NAME = "' .. program_name .. '"'
      )
      write_file("build.lua", content)
    end
  end

  -- Update run.lua if it exists
  if path_exists("run.lua") then
    local content, err = read_file("run.lua")
    if content then
      content = content:gsub(
        'local PROJECT_NAME = "quick"',
        'local PROJECT_NAME = "' .. program_name .. '"'
      )
      write_file("run.lua", content)
    end
  end
end

function open_editor(file_path)
  if file_path and file_path ~= "" then
    local cmd = "nvim " .. escape_path(file_path)
    os.execute(cmd)
  else
    os.execute("nvim")
  end
end

function to_kebab_case(str)
  return str:lower():gsub("[%s_]+", "-"):gsub("[^%a%d%-]", "")
end

function create_astro_project(site_name)
  local dir_name = to_kebab_case(site_name)

  if path_exists(dir_name) then
    print("Directory '" .. dir_name .. "' already exists")
    return false
  end

  local template_dir = path_join(REPOS, "quicks", "astro")
  if not path_exists(template_dir) then
    print("Template directory not found: " .. template_dir)
    return false
  end

  local success, _ = copy_directory(template_dir, dir_name)
  if not success then
    print("Error copying template directory")
    return false
  end

  local domain = site_name:lower():gsub("%s+", "") .. ".com"
  local description = "Welcome to " .. site_name .. "."

  local files_to_update = {
    path_join(dir_name, "astro.config.mjs"),
    path_join(dir_name, "src", "layouts", "Layout.astro"),
    path_join(dir_name, "src", "pages", "index.astro"),
  }

  for _, file_path in ipairs(files_to_update) do
    local content, err = read_file(file_path)
    if content then
      content = content:gsub("{{SITENAME}}", site_name)
      content = content:gsub("{{DOMAIN}}", domain)
      content = content:gsub("{{DESCRIPTION}}", description)
      content = content:gsub("{{OG_IMAGE}}", "/og.png")
      write_file(file_path, content)
    else
      print("Warning: " .. (err or "could not read " .. file_path))
    end
  end

  local main_file = path_join(dir_name, "src", "pages", "index.astro")
  open_editor(main_file)
  return true
end

function create_csharp_project(program_name)
  if path_exists(program_name) then
    print("Directory '" .. program_name .. "' already exists")
    return false
  end

  local dotnet_cmd = "dotnet new console -n "
    .. program_name
    .. " --use-program-main"
  local result, _, exit_code = os.execute(dotnet_cmd)

  if not result then
    print("Error creating C# project")
    return false
  end

  -- Change to the new directory and open editor
  local cd_cmd = "cd " .. escape_path(program_name)
  if is_windows() then
    os.execute(cd_cmd .. " && nvim Program.cs")
  else
    os.execute(cd_cmd .. "; nvim Program.cs")
  end

  return true
end

function process_c_cpp_template(program_name, language)
  local extension = (language == "cpp") and ".cpp" or ".c"
  local main_file = ""

  -- Rename the source file
  local old_path = path_join("src", "quick.c")
  local new_path = path_join("src", program_name .. extension)

  if path_exists(old_path) then
    local success, exit_code = move_file(old_path, new_path)
    if success then
      main_file = new_path
      update_file_content(main_file, program_name)
    else
      print("Error renaming source file")
    end
  end

  -- Update build files
  update_tooling_files(program_name, language)

  return main_file
end

function quick(language, program_name)
  if not language or not program_name then
    print("Usage: lua quick.lua <language> <program_name>")
    print("Supported languages: c, cpp, cs, ts, odin, rust, astro")
    return
  end

  language = language:lower()

  local template_mapping = {
    c = "c",
    cpp = "c", -- cpp uses the same template as c
    cs = "csharp",
    ts = "ts",
    odin = "odin",
    rust = "rust",
    astro = "astro",
  }

  if not template_mapping[language] then
    print("Unsupported language: " .. language)
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

  -- Check if directory already exists
  if path_exists(program_name) then
    print("Directory '" .. program_name .. "' already exists")
    return
  end

  -- Copy template
  local template_subdir = template_mapping[language]
  local base_template_dir = path_join(REPOS, "quicks")
  local template_dir = path_join(base_template_dir, template_subdir)

  if not path_exists(template_dir) then
    print("Template directory not found: " .. template_dir)
    return
  end

  local success, exit_code = copy_directory(template_dir, program_name)
  if not success then
    print("Error copying template directory")
    return
  end

  -- Change to the new directory
  local original_dir = os.getenv("PWD") or "."
  if not os.execute("cd " .. escape_path(program_name)) then
    print("Error changing to directory: " .. program_name)
    return
  end

  local main_file = ""

  -- Language-specific processing
  if language == "c" or language == "cpp" then
    main_file = process_c_cpp_template(program_name, language)
  elseif language == "ts" then
    main_file = "index.ts"
  elseif language == "odin" then
    -- Placeholder for future odin template processing
    main_file = ""
  elseif language == "rust" then
    -- Placeholder for future rust template processing
    main_file = ""
  end

  open_editor(main_file)
end

-- Main execution
if arg and #arg >= 2 then
  quick(arg[1], arg[2])
else
  print("Usage: lua quick.lua <language> <program_name>")
  print("Supported languages: c, cpp, cs, ts, odin, rust, astro")
end
