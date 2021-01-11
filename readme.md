# Lexpar (Working title)

A WIP lexer and parser generator, written in Terra

## Requirements

Terra is required to run the scripts in this repo. If you utilize the default shebang method to execute you will need terra installed at `/bin/terra`.

Terra can be downloaded [here](https://github.com/terralang/terra/releases), at the time of writing the latest version was Beta2, and this is the version the scripts are tested with.

## Usage

### Running the generators

Currently, only the lexer generator is fully functional. To use it you may run `./lex/cli.t`, see the output for help with commands. If you would like a standalone compact version, you can download one in releases or build one yourself with `./meta/concatenate.t ./lex/cli.t ./lpi`


### Lexer definition syntax

Each kind of token your generated lexer will support is defined with a rule or set of rules. The basic syntax for these rules is as follows:
```
rule_name = rule_pattern ;
```

Multiple patterns for the same rule are supported either with group unions:
```
rule_name = (rule_pattern_a) | (rule_pattern_b) ;
```
Or by binding the same rule name multiple times:
```
rule_name = rule_pattern_a ;
rule_name = rule_pattern_b ;
```


The pattern syntax is mostly equivalent to regex with some limitations and modifications

+ Freestanding ascii characters are allowed, except whitespace and control characters (e.g. `[` must be escaped, because it begins a set)

+ Whitespace is ignored unless escaped, typical escapes are accepted, and spaces are escaped with `\s`

+ Unicode escapes take the form `\u{}` with the interior of the `{}` containing 1 to 6 hexadecimal digits, inclusive. The resulting unicode character is not validated.
  - e.g. `\u{1f499}` inserts a blue heart 💙

+ Characters enclosed in `[` `]` define sets of characters valid at a given position
  - A leading `^` inverts the set (e.g. `[^\n\r]` matches everything but the newline and carriage return characters)
  - The range syntax `A-Z` is supported
  - Standard escapes `\n` are supported
  - Unicode escapes `\u{1F4A9}` are supported

+ Sequences of elements can be grouped with `(` `)`

+ Repetition modifiers are provided:
  - Modifiers bind only to the last proceeding element, for larger bindings the grouping operators must be used
  - `?` matches 0 or 1
  - `*` matches 0 or N
  - `+` matches 1 or N

+ Union operator `|` is provided:
  - Unions bind tightly to the elements immediately proceeding and following them, for larger bindings the grouping operators must be used
  - `a|b` matches the character a or the character b

+ `.` wildcard is not supported

### Running generated lexers

After linking your program with the generated lexer object, usage is quite simple.

Create a new lexer instance with `lex_new`, and consume characters with `lex_next_token`. The rule name associated with a given token can be acquired with `lex_token_name`, and a "slice" of the source text associated with a token can be acquired with `lex_substr`

```c
#include <stdio.h>
#include "./your_lexer.h"

/////////////////////////////////

Lexer lexer = lex_new(source_text, source_length);

LexResult result;
do {
  result = lex_next_token(&lexer);
  LexSubstr sub = lex_substr(&lexer, result.first, result.last);
  printf("%s: %.*s\n", lex_token_name(result.kind), sub.length, sub.src);
} while (result.kind != 0);
```