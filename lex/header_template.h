#ifndef LEXER_DEF
#define LEXER_DEF

#include <stdint.h>

typedef struct {
	char const* src;
	uint32_t length;

	uint32_t offset;

	int32_t curr_char;
	uint32_t curr_size;
} Lexer;

typedef struct {
	uint32_t kind;
	uint32_t first;
	uint32_t last;
} LexResult;

typedef struct {
	uint32_t length;
	char const* src;
} LexSubstr;

extern Lexer lex_new (char const* src, uint32_t length);
extern LexResult lex_next_token (Lexer* lexer);
extern LexSubstr lex_substr (Lexer* lexer, uint32_t first, uint32_t last);
extern char const* lex_token_name (uint32_t kind);

enum LexKinds {
	LEX_NIL = 0,
#pragma LEX_KIND_BODY
};

#endif