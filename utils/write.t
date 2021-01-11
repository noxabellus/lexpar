return function (path, content)
  local f = io.open(path, "w+")

  if f == nil then return false end

  f:write(content)

  f:close()

  return true
end