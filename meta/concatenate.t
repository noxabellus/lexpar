#! /bin/terra

blacklist = {
  "std"
}

require "utils/table"

table(blacklist)

local entry_point = assert(arg[1], "Expected a main file path")
local output = assert(arg[2], "Expected an output path")


local base_read = require "utils/read"
local write = require "utils/write"
local to_string = require "utils/to_string"


function read (path)
  local tries = table { }

  local c = base_read(path)
  if c then
    return c, path
  else
    tries:insert(path)
  end

  for m in package.path:gmatch("[^;]+") do
    local lpath = m:gsub("?", path)
    local lc = base_read(lpath)
    if lc then
      return lc, lpath
    else
      tries:insert(lc)
    end
  end

  for m in package.terrapath:gmatch("[^;]+") do
    local tpath = m:gsub("?", path)
    local tc = base_read(tpath)
    if tc then
      return tc, tpath
    else
      tries:insert(tc)
    end
  end

  error("Failed to load path `"..path.."`, tried:\n"..tries:concat("\n"))
end

function string.match_table (str, val)
  local res = table { }
  for m in str:gmatch(val) do
    res:insert(m)
  end
  return res
end

function string.lines (str)
  return str:match_table "[^\r\n]+"
end



function traverse (path, loaded, header)
  if blacklist:icontains(path) then return end
  if loaded[path] then return end

  local src = read(path)
  local require_paths = src:match_table("require (%b\"\")"):imap(function (v) return v:sub(2,-2) end)

  for _, req in ipairs(require_paths) do
    traverse(req, loaded, header)
  end

  loaded[path] = true
  header:insert({ path, src })
end

local loaded = { }
local header = table { }
traverse(entry_point, loaded, header)


local header_template =
[[
package.preload["%s"] = function ()
%s
end
]]


local main = base_read(entry_point)

main = main:gsub("#! /bin/terra+", "")

main = main:gsub("read (%b\"\")", function (x)
  local path = x:sub(2,-2)
  return "[["..assert(base_read(path), "Failed to read "..path).."]]"
end)


write(
  output,
  "#! /bin/terra\n"
  ..header
    :imap(function (v)
      if v[1] == entry_point then return nil end
      return header_template:format(v[1], v[2])
    end)
    :concat "\n"
  ..main
)

io.popen("chmod +x "..output)