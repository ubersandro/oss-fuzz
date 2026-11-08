/* Pure intra-object overflow with matching types: TySan should stay silent. */
#include <stdio.h>
struct P { int a; int b; } s;
int iob_main(int argc, char **argv) { int *pa = &s.a; pa[argc] = 5; printf("%d\n", s.b); return 0; }
