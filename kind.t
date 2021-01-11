local function make_kind (name, meta)
	local have_meta = type(meta) == "table"
	local super = have_meta and meta.super
	local builder = have_meta and (meta.builder or function (...) return ... end)

	return setmetatable({
		__name = name,
		__kind = name,
	}, {
		__index = super,
		__tostring = function (self)
			local s = name.."{"
			for k, v in pairs(s) do
				s = s..k..":"..v..", "
			end
			return s
		end,
		__call = function (kind, ...) return setmetatable(builder(...), { __index = kind }) end
	})
end

local function kind (t)
	return t.__kind or type(t)
end

return {
	make_kind,
	kind
}