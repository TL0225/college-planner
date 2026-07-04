#ifndef COLLEGE_TYPST_H
#define COLLEGE_TYPST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Compile Typst source UTF-8 to PDF bytes.
/// On success returns a heap pointer; writes length to *out_len.
/// On failure returns NULL; read college_typst_last_error().
/// *out_len is zero-initialized before any fallible work.
uint8_t *college_typst_compile_pdf(const char *source_utf8, size_t *out_len);

/// Free a buffer returned by college_typst_compile_pdf.
void college_typst_free(uint8_t *ptr, size_t len);

/// Thread-local error message valid until the next call on this thread.
const char *college_typst_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* COLLEGE_TYPST_H */
