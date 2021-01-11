require "utils/table"

local std = require "std"

local _, kind = unpack(require "kind")


local debug = macro(function(fmt, ...)
  local fmt = fmt:asvalue().."\n"
  local args = { ... }
  return `std.printf(fmt, [ args ])
end)

local no_debug = macro(function ()
  return quote end
end)

local terra bstr (b: bool): rawstring
  if b
    then return "true"
    else return "false"
  end
end

local function gen_atom (atom, dbg)
  if atom.kind == "char" then
    return macro(function (lex)
      return quote
        dbg("char %d (%c) == %d (%c)", [atom.value:byte()], [int8]([atom.value:byte()]), lex:curr(), [int8](lex:curr()))
        var ok = lex:curr() == [ atom.value:byte() ]

        if ok then lex:advance() end
        dbg("--ch %s", bstr(ok))
      in
        ok
      end
    end)
  elseif atom.kind == "unicode" then
    return macro(function (lex)
      return quote
        dbg("unicode %d (%c) == %d (%c)", [atom.value], [int8]([atom.value]), lex:curr(), [int8](lex:curr()))
        var ok = lex:curr() == [ atom.value ]

        if ok then lex:advance() end
        dbg("--uni %s", bstr(ok))
      in
        ok
      end
    end)
  else
    error "Invalid atom kind"
  end
end

local function gen_range (rng, dbg)
  local a, b = rng[1], rng[2]

  if a.kind == "char" then
    a = a.value:byte()
  elseif a.kind == "unicode" then
    a = a.value
  else
    error "Invalid range atom kind"
  end

  if b.kind == "char" then
    b = b.value:byte()
  elseif b.kind == "unicode" then
    b = b.value
  else
    error "Invalid range atom kind"
  end

  return macro(function (lex)
    return quote
      var curr = lex:curr()
      dbg("range %d <- %d -> %d", [a], curr,[b])
      var ok = curr >= [ a ] and curr <= [ b ]

      if ok then lex:advance() end
      dbg("--rng %s", bstr(ok))
    in
      ok
    end
  end)
end

local function gen_set_elem (selem, dbg)
  if kind(selem) == "atom" then
    return gen_atom(selem, dbg)
  elseif kind(selem) == "range" then
    return gen_range(selem, dbg)
  else
    error "Invalid set element"
  end
end

local function gen_set (rng, dbg)
  local element_exprs = rng.elements:imap(function (e) return gen_set_elem(e, dbg) end)
  local invert = rng.is_inverted

  return macro(function (lex)
    local expr = element_exprs[1]
    local q = `expr(lex)

    for i = 2, #element_exprs do
      expr = element_exprs[i]
      q = `[ q ] or expr(lex)
    end

    if invert then
      q = `not [ q ]
    end

    return quote
      dbg("set")
      var ok = [ q ]
      dbg("--set %s", bstr(ok))
      if [ invert ] then
        if ok then
          dbg("--set inv advances on ok")
          lex:advance()
        end
      end
    in
      ok
    end
  end)
end

local gen_elem

local function gen_group (grp, dbg)
  local element_exprs = grp:imap(function (e) return gen_elem(e, dbg) end)

  return macro(function (lex)
    local expr = element_exprs[1]
    local q = `expr(lex)

    for i = 2, #element_exprs do
      expr = element_exprs[i]
      q = `[ q ] and expr(lex)
    end

    return quote
      dbg("group")
      var mark = lex:mark()
      var ok = [ q ]

      if not ok then
        lex:backtrack(mark)
      end
      dbg("--grp %s", bstr(ok))
    in
      ok
    end
  end)
end

local function gen_modifier (mod, dbg)
  local expr = gen_elem(mod.expr, dbg)

  if mod.kind == "+" then
    return macro(function (lex)
      return quote
        dbg("mod +")
        var ok = expr(lex)

        if ok then
          var valid: bool
          repeat
            dbg("-- + rep")
            valid = expr(lex)
          until not valid
        end
      in
        ok
      end
    end)
  elseif mod.kind == "*" then
    return macro(function (lex)
      return quote
        dbg("mod *")
        if expr(lex) then
          var valid: bool
          repeat
            dbg("-- * rep")
            valid = expr(lex)
          until not valid
        end
      in
        true
      end
    end)
  elseif mod.kind == "?" then
    return macro(function (lex)
      return quote
        dbg("mod ?")
        expr(lex)
      in
        true
      end
    end)
  end
end

local function gen_union (un, dbg)
  local a = gen_elem(un[1], dbg)
  local b = gen_elem(un[2], dbg)

  return macro(function (lex)
    return quote
      dbg("union")
      var ok = a(lex) or b(lex)
      dbg("--un %s", bstr(ok))
    in
      ok
    end
  end)
end

gen_elem = function (elem, dbg)
  if kind(elem) == "atom" then
    return gen_atom(elem, dbg)
  elseif kind(elem) == "set" then
    return gen_set(elem, dbg)
  elseif kind(elem) == "group" then
    return gen_group(elem, dbg)
  elseif kind(elem) == "modifier" then
    return gen_modifier(elem, dbg)
  elseif kind(elem) == "union" then
    return gen_union(elem, dbg)
  else
    error "Invalid element kind"
  end
end

local function gen_pattern (patt, dbg)
  return gen_group(patt, dbg)
end

return function (rls, enable_debug)
  local dbg
  if enable_debug
    then dbg = debug
    else dbg = no_debug
  end

  local rules = { }
  local rule_count = 0

  local discriminators = { }
  local discriminator_names = table { }

  local discard

  for i, rl in ipairs(rls) do
    local rule_expr = gen_pattern(rl.pattern, dbg)

    if rl.name == "_" then
      if discard then
        local existing_expr = discard
        discard = macro(function (lex)
          return `existing_expr(lex) or rule_expr(lex)
        end)
      else
        discard = rule_expr
      end
    else
      local existing = rules[rl.name]
      if existing then
        local existing_expr = existing.expr
        existing.expr = macro(function (lex)
          return `existing_expr(lex) or rule_expr(lex)
        end)
      else
        rule_count = rule_count + 1

        discriminators[rl.name] = rule_count
        discriminator_names:insert(rl.name)
        
        rules[rl.name] = {
          index = rule_count,
          expr = rule_expr
        }
      end
    end
  end


  local struct Lexer {
    src: rawstring,
    length: uint32,

    offset: uint32,

    curr_char: int32,
    curr_size: uint32
  }

  local struct LexResult {
    kind: uint32,
    first: uint32,
    last: uint32
  }



  local function b (bin)
    return constant(uint8, `[ tonumber(bin, 2) ])
  end

  local byte_masks = table { 
    { b'11111000', b'11110000' },
    { b'11110000', b'11100000' },
    { b'11100000', b'11000000' },
    { b'10000000', b'00000000' },
  }
  
  terra Lexer.methods.char_size (byte: uint8): uint32
    escape
      for i, masks in ipairs(byte_masks) do
        emit quote
          if (byte and [ masks[1] ]) == [ masks[2] ] then
            return [ 5 - i ]
          end
        end
      end
    end

    return 0
  end

  Lexer.methods.char_size:setinlined(not enable_debug)


  terra Lexer:curr (): int32
    return self.curr_char
  end

  Lexer.methods.curr:setinlined(not enable_debug)


  terra Lexer:advance ()
    self.offset = self.offset + self.curr_size
    
    var bytes = self.src + self.offset
    self.curr_size = Lexer.char_size(@bytes)
    dbg("reading from %c at %u, got size of %u bytes", bytes[0], self.offset, self.curr_size)
    
    if self.curr_size == 1 then
      self.curr_char = bytes[0]
    elseif self.curr_size == 2 then
      self.curr_char = ((bytes[0] and 31) << 6) or (bytes[1] and 63)
    elseif self.curr_size == 3 then
      self.curr_char = ((bytes[0] and 15) << 12) or ((bytes[1] and 63) << 6) or (bytes[2] and 63)
    elseif self.curr_size == 4 then
      self.curr_char = ((bytes[0] and 7) << 18) or ((bytes[1] and 63) << 12) or ((bytes[2] and 63) << 6) or (bytes[3] and 63)
    else
      self.curr_char = 0xFFFFFF
    end
  end


  terra Lexer:mark (): uint32
    return self.offset
  end

  Lexer.methods.mark:setinlined(not enable_debug)


  terra Lexer:backtrack (offset: uint32)
    self.offset = offset
    self.curr_size = 0
    self:advance()
  end

  Lexer.methods.backtrack:setinlined(not enable_debug)


  terra Lexer:substr (first: uint32, last: uint32): { uint32, rawstring }
    return last - first, self.src + first
  end


  terra Lexer.methods.new (src: rawstring, length: uint32): Lexer
    var self = Lexer {
      src = src,
      length = length,

      offset = 0,

      curr_char = 0xFFFFFF,
      curr_size = 0
    }

    self:advance()

    return self
  end


  terra Lexer:next_token (): LexResult
    escape
      if discard then
        emit quote
          if discard(self) then
            dbg("discarded, recursing")
            return self:next_token()
          else
            dbg("did not discard")
          end
        end
      end
    end

    var first = self:mark()
    var kind: uint32 = 0

    escape
      for name, rule in pairs(rules) do
        emit quote
          dbg("\ntrying %s", name)
          if [ rule.expr ](self) then
            dbg("\nmatched %s", name)
            kind = [ rule.index ]
            goto ret
          else
            dbg("\nfailed to match %s", name)
          end
          dbg("")
        end
      end
    end

    ::ret::
    return LexResult { kind = kind, first = first, last = self:mark() }
  end
  

  terra Lexer.methods.token_name (kind: uint32): rawstring
    escape
      for name, desc in pairs(discriminators) do
        emit quote
          if kind == [ desc ] then
            return [ name ]
          end
        end
      end
    end

    return "nil"
  end

  return Lexer, LexResult, discriminator_names
end