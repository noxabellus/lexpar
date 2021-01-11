require "utils/table"

local escapes = {
	[" "] = "s",
	["\r"] = "r",
	["\n"] = "n",
	["\t"] = "t",
}

local function escape_str (s)
	local out = table {}

	for ch in s:gmatch "." do
		local esc = escapes[ch]
		if esc
			then out:iappend { "\\", esc }
			else out:insert(ch)
		end
	end

	return out:concat()
end

local function to_string (tt, escape_strs, print_addr, indent, done)
	if escape_strs == nil then escape_strs = true end
	done = done or { }
	indent = indent or 1
	
	if type(tt) == "table" then
		local addr = tostring(tt):match "0x.*"
		done[tt] = addr

		local sb = table { }

		if tt.__name then sb:insert(tt.__name.." ") end

		if print_addr then sb:insert(addr.." ") end
		
		sb:insert("{\n")

		for key, value in pairs(tt) do
			sb:insert(("  "):rep(indent))

			if type(key) ~= "number" then
				local key_addr = done[key]
				if not done[key] then
					sb:insert(to_string(key, escape_strs, print_addr, indent + 1, done))
				else
					sb:insert("[TREE_RECURSE "..key_addr.."]")
				end

				sb:insert(" = ")
			end

			local value_addr = done[value]
			if not value_addr then
				sb:insert(to_string(value, escape_strs, print_addr, indent + 1, done))
			else
				sb:insert("[TREE_RECURSE "..value_addr.."]")
			end
			sb:insert("\n")
		end

		sb:insert(("  "):rep(indent - 1))
		sb:insert("}")

		return sb:concat()
	elseif type(tt) == "boolean" then
		return tt and "true" or "false"
	elseif type(tt) == "string" then
		if escape_strs
			then return escape_str(tt)
			else return tt
		end
	elseif type(tt) == "nil" then
		return "nil"
	else
		return tostring(tt)
	end
end

return to_string