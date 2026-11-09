/* Allocators whose memory FSan tags with another layout than the one they hand
 * out. Expected results of AllocatorTypes.ql are marked [types] (alloc_type.c
 * has more: one per allocator and type there marked [type]), those of
 * ArenaAllocator.ql [arena], AllocatorPunning.ql [type],
 * CustomAllocatorStruct.ql [alloc] and StructPunning.ql [pun]. */
#include <stdlib.h>
struct node2 { struct node2 *next; int v; };

/* Storage carved through a parameter: the allocator converts the memory itself. */
struct hpool { size_t used; char mem[4096]; };
struct hpool *hpool_new(void) { struct hpool *p; p = malloc(sizeof *p); p->used = 0; return p; }
struct node2 *node2_alloc(struct hpool *p) {          /* [types] struct.hpool, used as struct node2; [arena] */
  struct node2 *n = (struct node2 *)(p->mem + p->used);
  p->used += sizeof *n;
  return n;
}

/* Storage in a struct nested in a static object, like CPython's dtoa state:
 * the entry is the nested struct, not the whole object. */
struct big2 { struct big2 *next; int k, wds; unsigned x[1]; };
struct dtoa_like { double prealloc[288]; double *next; };
struct runtime { int initialized; struct dtoa_like dtoa; };
static struct runtime RT;
void rt_init(void) { RT.dtoa.next = RT.dtoa.prealloc; }
struct big2 *big2_alloc(int len) {                    /* [types] struct.dtoa_like, used as struct big2; [arena] */
  struct big2 *rv = (struct big2 *)RT.dtoa.next;
  RT.dtoa.next += len;
  return rv;
}

/* Not [types]: the storage holds the type it hands out. */
struct npool { struct node2 nodes[64]; int used; };
static struct npool NP;
struct node2 *npool_get(void) { return &NP.nodes[NP.used++]; }   /* [arena] */

/* Not [types]: the allocated type is the first part of the one it is used as. */
struct base2 { int kind; };
struct derived2 { int kind; int x; };
void *base_alloc(void) { struct base2 *b; b = malloc(sizeof(struct base2)); return b; }
void use_types(void) { struct derived2 *d = base_alloc(); (void)d; }   /* [type] [alloc] [pun] */
