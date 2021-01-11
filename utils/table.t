setmetatable(table, {
	__call = function (_, tbl)
		if tbl == nil then tbl = { } end
		return setmetatable(tbl, { __index = table })
	end
})


function table:last ()
	return self[#self]
end

function table:iappend (rhs)
	for i, v in ipairs(rhs) do
		table.insert(self, v)
	end

	return self
end

function table:imap (f, out)
	out = out or table { }

	for i, v in ipairs(self) do
		local x = f(v, i, self)
		if x ~= nil then
			table.insert(out, x)
		end
	end

	return out
end

function table:index_of (x)
	for i, y in ipairs(self) do
		if x == y then
			return i
		end
	end

	return 0
end

function table:icontains (x)
	return table.index_of(self, x) ~= 0
end