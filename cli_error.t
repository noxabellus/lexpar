local function cli_error(msg)
	io.stderr:write(msg.."\n")
	os.exit(1)
end

local function cli_assert(cond, msg)
	if cond then
		return cond
	else
		cli_error(msg)
	end
end

return { cli_error, cli_assert }