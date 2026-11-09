/* Custom allocators whose memory has one struct type and is used as another.
 * Expected results of AllocatorPunning.ql are marked [type], those of
 * CustomAllocatorStruct.ql [alloc], ArenaAllocator.ql [arena] and
 * StructPunning.ql [pun]. */
#include <stdlib.h>
struct object { struct object *next; long data[7]; };
struct foo { int a; float b; };
struct bar { char tag; double d; };

/* A typed pool: the memory is a struct object, whatever the caller makes of it. */
void *obj_alloc(void) { struct object *o = malloc(sizeof *o); return o; }
void *cell_alloc(void) { return malloc(sizeof(struct object)); }        /* typed by sizeof */
void *obj_alloc_wrapped(void) { void *p = obj_alloc(); return p; }      /* wraps a typed allocator */

/* Perl's op slabs (op.c, simplified): ops are carved out of calloc'ed struct
 * opslab memory and handed out as OP, which NewOp casts to the op's type. */
typedef struct op { struct op *op_next; unsigned short op_type; } OP;
typedef struct unop { struct op *op_next; unsigned short op_type; OP *op_first; } UNOP;
typedef struct listop { struct op *op_next; unsigned short op_type; OP *op_first, *op_last; } LISTOP;
typedef struct opslot OPSLOT;
typedef struct opslab OPSLAB;
struct opslot { OPSLOT *opslot_next; OPSLAB *opslot_slab; OP opslot_op; };
struct opslab { OPSLOT *opslab_first; OPSLAB *opslab_next; OP *opslab_freed; OPSLOT opslab_slots; };

static OPSLAB *new_slab(size_t sz) {
  OPSLAB *slab = (OPSLAB *)calloc(sz, sizeof(void *));
  slab->opslab_first = (OPSLOT *)((void **)slab + sz - 1);
  return slab;
}
static OP *compcv_start;                            /* CvSTART(PL_compcv) */
void *Slab_Alloc(size_t sz) {                       /* [arena] free list opslab.opslab_freed */
  OPSLAB *slab, *slab2;
  OPSLOT *slot;
  OP *o;
  if (sz > 4096) { o = (OP *)calloc(1, sz); return (void *)o; }
  if (!compcv_start)
    compcv_start = (OP *)(slab = new_slab(64));     /* [type] struct opslab : struct op; [alloc] twice, here and via compcv_start */
  else
    slab = (OPSLAB *)compcv_start;                  /* [pun] struct op : struct opslab */
  if ((o = slab->opslab_freed)) { slab->opslab_freed = o->op_next; return (void *)o; }
  slab2 = slab->opslab_next ? slab->opslab_next : slab;
  if ((size_t)((void **)slab2->opslab_first - (void **)&slab2->opslab_slots) < sz) {
    slab2 = new_slab(128);
    slab2->opslab_next = slab->opslab_next;
    slab->opslab_next = slab2;
  }
  slot = (OPSLOT *)((void **)slab2->opslab_first - sz);
  slot->opslot_slab = slab;
  slot->opslot_next = slab2->opslab_first;
  slab2->opslab_first = slot;
  o = &slot->opslot_op;
  return (void *)o;
}
#define NewOp(var, type) (var = (type *)Slab_Alloc(sizeof(type)))

/* A static pool whose buffer is a member: the memory is a struct pool. */
struct pool { size_t used; char buf[4096]; };
static struct pool P;
void *pool_get(size_t n) { void *p = P.buf + P.used; P.used += n; return p; }   /* [arena] */

/* A region that keeps a cursor into its own buffer: the memory is a struct region. */
struct region { char *cur; char mem[1 << 16]; };
struct region *region_new(void) { struct region *r = malloc(sizeof *r); r->cur = r->mem; return r; }
void *region_alloc(struct region *r, size_t n) { char *p = r->cur; r->cur += n; return p; }  /* [arena] */

void use_allocators(struct region *rg) {
  LISTOP *l1, *l2;
  UNOP *u;
  OP *o;
  NewOp(l1, LISTOP);                                /* [type] struct opslab, struct op : struct listop; [alloc] [pun] */
  NewOp(l2, LISTOP);                                /* [alloc] [pun]; [type] counted with l1 */
  NewOp(u, UNOP);                                   /* [type] struct opslab, struct op : struct unop; [alloc] [pun] */
  NewOp(o, OP);                                     /* [type] struct opslab : struct op; [alloc] */
  struct foo *f = obj_alloc();                      /* [type] struct object : struct foo; [alloc] [pun] */
  struct bar *b = cell_alloc();                     /* [type] struct object : struct bar; [alloc] */
  struct bar *b3 = obj_alloc_wrapped();             /* [type] struct object : struct bar; [alloc] [pun] */
  struct foo *f2 = pool_get(sizeof *f2);            /* [type] struct pool : struct foo; [alloc] */
  struct bar *b2 = region_alloc(rg, sizeof *b2);    /* [type] struct region : struct bar; [alloc] */
  /* Not [type]: the allocated type is the type used. */
  struct object *ob = obj_alloc();                  /* [alloc] */
  struct region *r2 = region_new();
  (void)l1; (void)l2; (void)u; (void)o; (void)f; (void)b; (void)b3; (void)f2; (void)b2; (void)ob; (void)r2;
}
