/* Type punning: an object of type struct A accessed as struct B (FSan: field-tag
 * mismatch, not a bounds violation). Common initial sequence: none. */
#include <stdio.h>
#include <stdlib.h>
struct A { int kind; float value; };
struct B { int kind; int count; };
__attribute__((noinline)) int count_of(void *p) { return ((struct B *)p)->count; }
int main(int argc, char **argv) {
  struct A *a = malloc(sizeof *a);
  a->kind = 1; a->value = 2.5f;
  printf("%d\n", count_of(a));      /* reads a float object through an int lvalue */
  free(a); return 0;
}
