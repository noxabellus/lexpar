require "utils/table"

local to_string = require "utils/to_string"
local make_kind, kind = unpack(require "kind")

local function lexer (str, dbg)
	local lex = {
		_remainder = str,
		_dbg = dbg,
		_line = 0,
	}

	function lex:reconstitute ()
		if #self._remainder > 0 then
			if self._curr
				then return self._curr .. self._remainder
				else return self._remainder
			end
		else
			return self._curr
		end
	end

	function lex:curr ()
		if self._curr ~= ""
			then return self._curr
			else return nil
		end
	end

	function lex:advance ()
		repeat
			if self._curr == "\n" then
				self._line = self._line + 1
			end

			self._curr = self._remainder:sub(1, 1)
			self._remainder = self._remainder:sub(2)
		until not self._curr or not self._curr:match "%s"
	end

	local function eval_expected (ch, expected)
		if type(expected) == "function" or type(expected) == "table" then
			return expected(ch)
		elseif #expected > 1 then
			return ch:match(expected) ~= nil
		else
			return expected == ch
		end
	end

	function lex:next_if (expected)
		local ch = self:curr()
	
		if ch and eval_expected(ch, expected) then
			self:advance()
			return ch
		else
			return nil
		end
	end

	function lex:next_if_not (unexpected)
		local ch = self:curr()

		if ch and not eval_expected(ch, unexpected) then
			self:advance()
			return ch
		else
			return nil
		end
	end

	local function get_line (src)
		local x = src:match(".*\n")
		return x or src
	end

	function lex:error (err_msg)
		local msg = (self._line + 1)..": "..(err_msg or "Error")

		local line = get_line(self._remainder)
		if line then
			msg = msg.." (remaining line: "..line..")"
		end

		if self._dbg then
			msg = msg.."\n"..debug.traceback()
		end

		error(msg, 0)
	end

	function lex:assert (cond, err_msg)
		if not cond
			then self:error(err_msg)
			else return cond
		end
	end

	function lex:expect (expected, err_msg)
		return self:assert(self:next_if(expected), err_msg or "Expected `"..expected.."`")
	end

	function lex:dont_expect (unexpected, err_msg)
		return self:assert(self:next_if_not(unexpected), err_msg or "Did not expect `"..unexpected.."`")
	end

	lex:advance()

	return lex
end




local Range = make_kind("range", { builder = function (a, b) return { a, b } end })
local Atom = make_kind("atom", { builder = function (kind, ch) return { kind = kind, value = ch } end })
local Char = function (ch) return Atom("char", ch) end
local Unicode = function (num) return Atom("unicode", num) end
local Set = make_kind("set", { builder = function (is_inverted, elements) return { is_inverted = is_inverted, elements = elements } end })
local Group = make_kind("group", { super = table })
local Modifier = make_kind("modifier", { builder = function (kind, expr) return { kind = kind, expr = expr } end })
local Union = make_kind("union", { builder = function (a, b) return { a, b } end })
local Pattern = Group
local Rule = make_kind("rule", { builder = function (name, pattern) return { name = name, pattern = pattern } end })



local escapes = table {
	"[", "]",
	"(", ")",
	"{", "}",
	"\\", "\"", "\'",
	"^", "+", "-", "*", "?", "|",
	"=", ";",
}

local convertable_escapes = table { "n", "r", "t", "s" }

local lua_escapes = ("["..
	escapes
		:imap(function (v)
			return "%"..v
		end)
		:iappend(convertable_escapes)
		:concat()
.."]")

escapes:iappend(convertable_escapes)

local unescape_lit = {
	n = "\n",
	r = "\r",
	t = "\t",
	s = " ",
}

local function escape_code (lex)
	if lex:next_if "\\" then
		if lex:next_if "u" then
			lex:expect "{"

			local hex = ""
			repeat
				local ch = lex:next_if "[0-9a-fA-F]"
				if ch
					then hex = hex..ch
					else break
				end
			until #hex == 6

			lex:expect "}"

			local num = tonumber(hex, 16)
			if num < 128
				then return Char(string.char(num))
				else return Unicode(num)
			end
		else
			local x = lex:next_if(lua_escapes)
			if x
				then return Char(unescape_lit[x] or x)
				else lex:error "Invalid escape code sequence"
			end
		end
	end
end

local function charset (lex)
	if lex:next_if "[" then
		local is_inverted = lex:next_if "^" ~= nil
		local elements = table { },

		lex:assert(lex:curr() ~= "]", "Empty char set")
		
		local function get_elem ()
			local function get_ch ()
				local esc = escape_code(lex)
				if esc
					then return esc
					else return Char(lex:dont_expect("[%-%^%]]", "Unexpected character `"..lex:curr().."` in char set"))
				end
			end

			local left = get_ch()
			if lex:next_if "-"
				then return Range(left, get_ch())
				else return left
			end
		end

		repeat elements:insert(get_elem())
		until lex:next_if "]"
		
		return Set(is_inverted, elements)
	end
end

local function char (lex)
	local result = lex:next_if_not(lua_escapes)
	if result
		then return Char(result)
		else return nil
	end
end


local subpats

local function subpat (lex)
	for i, subpat in ipairs(subpats) do
		local x = subpat(lex)

		if x then
			return x
		end
	end

	return nil
end



local function element (lex)
	local left = subpat(lex)
	if left then
		local mod = lex:next_if "[%+%*%?]"
		if mod then
			left = Modifier(mod, left)
		end

		if lex:next_if "|"
			then return Union(left, element(lex))
			else return left
		end
	end
end

local function group (lex)
	if lex:next_if "(" then
		local grp = Group { }
		repeat
			local elem = element(lex)
			if elem
				then grp:insert(elem)
				else break
			end
		until lex:next_if ")"

		return grp
	end
end

subpats = table {
	escape_code,
	charset,
	char,
	group
}

local function pattern (lex)
	local patt = Pattern { }

	repeat
		local elem = element(lex)
		if elem
			then patt:insert(elem)
			else break
		end
	until false

	if #patt ~= 0
		then return patt
		else return nil
	end
end

local function identifier (lex)
	local ident = lex:next_if "[a-zA-Z_]"
	if ident then
		repeat
			local ch = lex:next_if "[a-zA-Z0-9_]"
			if ch
				then ident = ident..ch
				else break
			end
		until false
	end

	return ident
end

local function rule (lex)
	local name = identifier(lex)
	if name then
		lex:expect "="

		local patt = pattern(lex)
		assert(patt, " Expected a regular expression pattern to follow `"..name.." = ` in rule")

		return Rule(name, patt)
	end
end

return function (source, dbg)
	local lex = lexer(source, dbg)
	local rules = table { }
	
	repeat
		local r = rule(lex)

		if r
			then rules:insert(r)
			else break
		end
	until not lex:next_if ";"

	return rules, lex:reconstitute()
end