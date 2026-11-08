/* Custom allocators whose result becomes a struct. Expected results of
 * CustomAllocatorStruct.ql are marked [alloc]. */
#include <stdlib.h>
#include <string.h>
struct S { int a; float b; };
struct T { char name[8]; };
union U { int i; float f; };

static void *xmalloc(size_t n) { void *p = malloc(n); if (!p) abort(); return p; }
static void *xzalloc(size_t n) { void *p = xmalloc(n); memset(p, 0, n); return p; }  /* wraps a wrapper */

static char arena[1024];
static size_t used;
void *pool_alloc(size_t n) __attribute__((malloc, alloc_size(1)));                    /* no libc call inside */
void *pool_alloc(size_t n) { void *p = arena + used; used += n; return p; }

void f(void) {
  struct S *s = xmalloc(sizeof *s);                 /* [alloc] implicit conversion */
  struct T *t = (struct T *)xzalloc(sizeof *t);     /* [alloc] explicit cast */
  void *raw = pool_alloc(64);
  struct S *s2 = raw;                               /* [alloc] through a variable */
  /* Not reported: libc allocator, non-struct result, union. */
  struct S *s3 = malloc(sizeof *s3);
  char *buf = xmalloc(16);
  union U *u = xmalloc(sizeof *u);
  free(s); free(t); free(s3); free(buf); free(u); (void)s2;
}
