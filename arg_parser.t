require "utils/table"

local cli_error, cli_assert = unpack(require "cli_error")

local function arg_parser (args, in_arg_defs)
  if args[1] == "-h" or args[1] == "-help" or #args == 0 then
    print("Usage:\n")

    for i, v in ipairs(in_arg_defs) do
      print("-"..v[1].." / -"..v[2].."\n"..v[3].."\n")
    end

    if #args > 1 then
      print("Additional command line arguments after `-help`/`-h` are ignored")
    end

    os.exit(0)
  end

  local arg_defs = table { }
  local def_lookup = { }
  
  for i, v in ipairs(in_arg_defs) do
    local x = {
      name = v[1];
      shorthand = v[2];
      description = v[3];
      incompatible = v[4];
      display = "`-"..v[1].."`/`-"..v[2].."`";
      is_flag = v.is_flag;
    }

    if not x.is_flag then
      x.handler = v[5];
    end

    arg_defs:insert(x)

    def_lookup[v[1]] = i
  end

  local t = { }
  
  for i, arg in ipairs(args) do
    local found_match
    for j, def in ipairs(arg_defs) do
      local match = arg:match("^-"..def.name) or arg:match("^-"..def.shorthand)
      if match then
        cli_assert(t[def.name] == nil, "Duplicate definition for command line argument: "..def.display)

        for k, ic in ipairs(def.incompatible) do
          cli_assert(t[ic] == nil, "Cannot apply command line argument: "..def.display..", it is incompatible with preceeding argument: "..arg_defs[def_lookup[ic]].display)
        end
        
        local remainder = arg:sub(#match+1)
        
        if remainder:sub(1,1) == "=" then
          cli_assert(not def.is_flag, "Unexpected `=` following command line argument: "..def.display.." is a flag, and takes no data")

          remainder = remainder:sub(2)
        end

        if #remainder ~= 0 then
          cli_assert(not def.is_flag, "Unexpected data following command line argument: "..def.display.." is a flag, and takes no data")
          if def.handler ~= nil then
            remainder = def.handler(remainder)
          end

          t[def.name] = remainder
        else
          cli_assert(def.is_flag, "Expected data following command line argument: "..def.display)
          t[def.name] = true
        end
        
        found_match = true
        break
      end
    end

    if not found_match then
      if arg == "help" or arg == "h"
        then cli_error("`-help`/`-h` must be passed as the first and only parameter to receive documentation output")
        else cli_error("Unrecognized command line input: `"..arg.."`")
      end
    end
  end

  return t
end

local function flag (t)
  t.is_flag = true
  return t
end

local function option (t)
  t.is_flag = false
  return t
end



local function list (t)
  local function split (s, on)
    local t = table { }
    for m in s:gmatch("[^"..on.."]+") do
      t:insert(m)
    end
    return t
  end

  table.insert(t, function (f) return split(f, ", ") end)
  return option(t)
end


return { arg_parser, flag, option, list }