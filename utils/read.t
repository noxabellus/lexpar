return function (path)
  local f = io.open(path)

  if f == nil then return nil end
  
  local text = f:read "*a"

  f:close()

  return text
end