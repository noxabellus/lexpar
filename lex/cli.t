#! /bin/terra

require "utils/table"

local to_string = require "utils/to_string"
local read = require "utils/read"
local write = require "utils/write"
local parse = require "lex/parse"
local compile = require "lex/compile"
local std = require "std"
local arg_parser, cflag, coption, clist = unpack(require "arg_parser")
local cli_error, cli_assert = unpack(require "cli_error")

local args = arg_parser(arg, {
	cflag { "debug",         "d",     "Enable debug printing in generated code, and do not optimize output object", { } };
	cflag { "stdin",         "si",    "Read definition from stdin instead of a file",                               { "input" } };
	cflag { "stdout",        "so",    "Write compiled output object to stdout instead of a file",                   { "object" } };
	cflag { "stdout_header", "soh",   "Write generated header to stdout instead of a file",                         { "header" } };
	cflag { "floatabihard",  "fabih", "Use -mfloat-abi=hard with LLVM",                                             { } };

	coption { "input",  "i",  "Path to definition file to be compiled",                                            { "stdin" } };
	coption { "object", "o",  "Path to write compiled output object to",                                           { "stdout" } };
	coption { "type",   "t",  "The kind of object to write; overrides the kind auto-detected from file extension", { } };
	coption { "header", "ho", "Path to write generated header file to",                                            { "stdout_header" } };
	coption { "target", "t",  "Target triple for LLVM",                                                            { } };
	coption { "cpu",    "c",  "Target cpu for LLVM",                                                               { } };

	clist { "features", "f", "Target features for LLVM",                   { } };
	clist { "linker",   "l", "Flags to send to linker for binary objects", { } };
})



local debug = args.debug ~= nil

local def_path
local def
if args.stdin then
	def_path = "stdin"
	def = io.stdin:read()
else
	cli_assert(args.input, "Please provide an input definition path `-input=./path/to/source`")
	def_path = args.input
	def = read(def_path)
end

cli_assert(def, "Cannot load definition file from `"..def_path.."`")
cli_assert(#def ~= 0, "Cannot use empty definition file `"..def_path.."`")

local lex_rules
local ok, err = pcall(function ()
	local remaining_def
	lex_rules, remaining_def = parse(def, true)

	cli_assert(remaining_def == nil or #remaining_def == 0, "Unparseable source remains in lexer def file: [["..remaining_def.."]]")
	
	return lex_rules
end)

cli_assert(ok, ""..def_path..":"..to_string(err))
cli_assert(#lex_rules > 0, "Expected at least one lexical rule")



local Lexer, LexResult, discriminators = compile(lex_rules, debug)


local sym_table = {
	lex_new = Lexer.methods.new,
	-- lex_advance = Lexer.methods.advance,
	lex_next_token = Lexer.methods.next_token,
	lex_token_name = Lexer.methods.token_name,
	lex_substr = Lexer.methods.substr,
}

local target = nil
if args.target then
	target = terralib.newtarget {
		Triple = args.target,
		CPU = args.cpu,
		Features = args.features,
		FloatABIHard = args.floatabihard
	}
end

local object_types = {
	object = ".o",
	asm = ".s",
	llvmir = ".ll",
	bitcode = ".bc",
	sharedlibrary = { ".so", ".dylib", ".dll" },
}

local printable_object_types = table { }
for k, _ in pairs(object_types) do
	printable_object_types:insert(k)
end

if args.type then
	cli_assert(object_types[args.type], "Unsupported output type `"..args.type.."`, allowed values are: "..printable_object_types:concat ", ")
end

if args.stdout then
	local ty = cli_assert(args.type, "When writing to stdout, an object type is required `-type`/`-t` (E.g. `-t=llvmir`)")

	cli_assert(ty ~= "sharedlibrary", "Shared library cannot be written to stdout")
	
	local s = terralib.saveobj(
		nil,
		ty,
		sym_table,
		args.linker,
		target,
		not debug
	)

	io.stdout:write(s)
else
	local output
	local ty
	if args.object then
		output = args.object
		if not args.type then
			for k, v in pairs(object_types) do
				local x
				if type(v) == "table"
					then x = v
					else x = { v }
				end
					
				for i, y in ipairs(x) do
					if output:match("%"..y.."$") then
						ty = k
						break
					end
				end
				
				if ty then break end
			end

			cli_assert(ty, "Cannot infer object type from output path `"..output.."`, please supply one explicitly with `-type`/`-t` or change the file extension")
		end
	elseif args.type then
		local extension = object_types[args.type]
		cli_assert(type(extension) == "string", "The specified object type `"..args.type.."` has varying extensions depending on the output target, please supply an explicit output path")
		output = "out"..extension
		ty = args.type
	else
		output = "out.o"
		ty = "object"
	end

	assert(ty ~= nil)

	terralib.saveobj(
		output,
		ty,
		sym_table,
		args.linker,
		target,
		not debug
	)
end



if args.stdout_header or args.header then
	local c_header = (read "./lex/header_template.h"):gsub(
		"#pragma LEX_KIND_BODY",
		discriminators:imap(function (v, i)
			return "\tLEX_"..v:upper().." = "..i
		end):concat ",\n"
	)

	if args.stdout_header then
		io.stdout:write(c_header)
	else
		write(args.header, c_header)
	end
end