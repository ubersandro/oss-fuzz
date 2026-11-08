/* Arena and recycler allocators. Expected results of ArenaAllocator.ql are
 * marked [arena], those of CustomAllocatorStruct.ql [alloc]. */
#include <stdlib.h>
struct arena { char *base; size_t used, cap; };
struct node { struct node *next; int payload[4]; };
struct recycler { struct node *free; size_t count; };
struct lexer { const char *name; };
struct obj { int a; };

struct arena *arena_new(size_t cap) {
  struct arena *a = malloc(sizeof *a);            /* the arena object */
  a->base = malloc(cap); a->used = 0; a->cap = cap;
  return a;
}
void *arena_alloc(struct arena *a, size_t n) {   /* [arena] struct arena, malloc in arena_new */
  if (a->used + n > a->cap) return NULL;
  void *p = a->base + a->used;
  a->used += n;
  return p;
}

static struct recycler R;
struct node *node_get(void) {                     /* [arena] struct recycler, static R */
  struct node *n = R.free;
  if (!n) return malloc(sizeof *n);
  R.free = n->next; R.count--;
  return n;
}
struct recycler *recycler_new(void) { return calloc(1, sizeof(struct recycler)); }
struct node *rec_get(struct recycler *r) {        /* [arena] struct recycler: calloc in recycler_new, or R */
  struct node *n = r->free;
  if (n) r->free = n->next;
  return n;
}

struct arena *global_arena;
void *my_alloc(size_t n) { return arena_alloc(global_arena, n); }  /* [arena] wraps arena_alloc */

/* Not an allocator: returns a field but updates nothing. */
const char *lexer_name(struct lexer *l) { return l->name; }

struct obj *new_obj(void) { struct obj *s = my_alloc(sizeof *s); return s; }  /* [alloc], [arena] wraps my_alloc */
