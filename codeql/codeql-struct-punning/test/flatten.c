/* Multidimensional arrays viewed as one flat array. Expected results are in
 * the comments: [flat] FlattenedArrayAccess, [escape] FlattenedArrayEscape. */
#include <string.h>
int A[3][3];
int G3[2][3][4];
int *gp;
struct holder { int *p; };

int consume(int *p, int n) { int s = 0; for (int i = 0; i < n; i++) s += p[i]; return s; } /* [flat] via escape() */
void rows(int (*r)[3]);

int sum_cast(void) {
  int *p = (int *)A, s = 0;
  for (int i = 0; i < 9; i++) s += *p++;            /* [flat] whole-array cast */
  return s;
}
int sum_addr(void) {
  int *p = &A[0][0], s = 0;
  for (int i = 0; i < 9; i++) s += p[i];            /* [flat] loop bound 9 > row length 3 */
  return s;
}
int const_off(void) { int *p = A[0]; return p[4]; }  /* [flat] constant 4 >= row length 3 */
int row_walk(int i) {
  int *r = A[i], s = 0;
  for (int j = 0; j < 3; j++) s += r[j];            /* [flat] may cross (stays in the row here) */
  return s;
}

void escape(struct holder *h) {
  int *p = (int *)A;
  consume(p, 9);                                    /* [escape] passed to consume */
  gp = &A[0][0];                                    /* [escape] stored in a global */
  h->p = A[1];                                      /* [escape] stored in a field */
}
int *ret(void) { return (int *)G3; }                /* [escape] returned (3-D) */

/* None of these is reported. */
int normal(int i, int j) { return A[i][j] + *A[i]; }
int one_d(void) { int B[9], *p = B, s = 0; for (int i = 0; i < 9; i++) s += p[i]; return s; }
void pass_rows(void) { rows(A); }                   /* pointer to rows: not flattened */
void clear(void) { memset(A, 0, sizeof A); }        /* mem* functions are not escapes */
