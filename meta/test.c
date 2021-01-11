#include <stdio.h>
#include <stdlib.h>
#include "../your_lexer.h"

int read_file (char const* path, char const** out_source, uint32_t* out_length) {
  FILE* f = fopen (path, "rb");
  if (f == NULL) return 0;

  fseek(f, 0, SEEK_END);
  uint32_t length = ftell(f);

  fseek (f, 0, SEEK_SET);

  char* buffer = malloc(length);
  if (buffer == NULL) return 0;
    
  fread(buffer, 1, length, f);

  fclose(f);

  *out_source = buffer;
  *out_length = length;

  return 1;
}



int main () {
  char const* source_text;
  uint32_t source_length;

  if (!read_file("./meta/test_srcs/basic.src", &source_text, &source_length)) return -1;
  
  /////////////////////////////////

  Lexer lexer = lex_new(source_text, source_length);

  LexResult result;
  do {
    result = lex_next_token(&lexer);
    LexSubstr sub = lex_substr(&lexer, result.first, result.last);
    printf("%s: %.*s\n", lex_token_name(result.kind), sub.length, sub.src);
  } while (result.kind != 0);

  return 0;
}