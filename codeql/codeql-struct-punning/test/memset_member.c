/* mem* writes that start at a struct member and run past it. Expected results
 * of MemsetOverMember.ql are marked [member]. */
#include <stddef.h>
#include <string.h>
#include <strings.h>
struct S { int a; char name[8]; int b; long c; };   /* a@0 name@4 b@12 c@16, size 24 */
struct N { struct S in; int tail; };

void clear_members(struct S *s, struct N *n, const struct S *src, size_t k) {
  memset(&s->a, 0, sizeof *s);                            /* [member] covers name, b, c */
  memset(s->name, 0, 12);                                 /* [member] covers b */
  memset(&s->name[4], 0, 8);                              /* [member] starts 4 bytes in, covers b */
  memset(&s->b, 0, sizeof(*s) - offsetof(struct S, b));   /* [member] covers c */
  memset(&n->in.b, 0, 16);                                /* [member] covers c, 4 bytes past S */
  bzero(&s->a, 8);                                        /* [member] covers name */
  memcpy(&s->b, &src->b, 12);                             /* [member] covers c */
  /* Not reported: fits the member, whole struct, size not constant. */
  memset(&s->name[0], 0, sizeof s->name);
  memset(&s->c, 0, sizeof s->c);
  memset(s, 0, sizeof *s);
  memset(s->name, 0, k);
}
