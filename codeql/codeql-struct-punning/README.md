# CodeQL: find FSan false-positive sources before fuzzing

| query | reports | test |
|---|---|---|
| `StructPunning.ql` | a struct pointer cast to an unrelated struct type | `pun.c`, `iob.c` |
| `PunnedTypes.ql` | each pair of struct types punned into each other, once | `pun.c` |
| `FlattenedArrayAccess.ql` | a multidimensional array traversed through a flat pointer | `flatten.c` `[flat]` |
| `FlattenedArrayEscape.ql` | a flat pointer into a multidimensional array passed, returned or stored | `flatten.c` `[escape]` |
| `MemsetOverMember.ql` | a `memset`/`bzero`/`memcpy`/`memmove` that starts at a member and runs past it | `memset_member.c` `[member]` |
| `CustomAllocatorStruct.ql` | a custom allocator call whose result becomes a struct pointer | `allocator.c`, `arena.c` `[alloc]` |
| `ArenaAllocator.ql` | an arena/recycler allocator, its arena struct type and where that object is instantiated | `arena.c` `[arena]` |

The expected results are marked in the test files. The test files share one
database, so they must not define the same global function twice: CodeQL merges
such functions, and data flow skips a function with two bodies.

```bash
codeql pack install .
codeql database create db --language=cpp --source-root=test --command="clang -c pun.c iob.c flatten.c allocator.c memset_member.c arena.c"
codeql database analyze db --rerun --format=sarif-latest --output=db.sarif .   # all queries
```

Keep `--rerun` after editing a query. Without it, `analyze` reuses the result
that an earlier run stored in the database (`No need to rerun`), and you get the
old messages.

## Reading the results

Each result is located at the code to look at: the cast, the access, the call or
the allocator. The message also gives `file:line` for everything it names, such
as struct and field definitions, where a pointer comes from, and where an arena
object is created. Paths are relative to the source root (`/src` in the OSS-Fuzz
images), as in the SARIF result locations.

This prints one `file:line: query: message` line per result:

```bash
jq -r '.runs[].results[] | .ruleId as $r | .locations[0].physicalLocation as $p | .message.text | split("\n")[] | "\($p.artifactLocation.uri):\($p.region.startLine): \($r | sub("^fsan/"; "")): \(gsub("(?<!\\\\)\\[(?<t>(?:[^\\[\\]\\\\]|\\\\.)*)\\]\\([0-9]+\\)"; .t) | gsub("\\\\(?<c>.)"; .c))"' db.sarif
```

```
pun.c:7: struct-punning: Pointer to struct A (pun.c:5) reinterpreted as struct B (pun.c:6). The struct A pointer comes from a (pun.c:11).
arena.c:15: arena-allocator: Custom allocator arena_alloc (carves from arena.base) hands out memory from arena.base (arena.c:4); arena object: allocated by malloc() (arena.c:11).
```

SARIF stores the names in the messages as links to their locations. The `jq`
command keeps only their text. CodeQL merges results that share a location and
a query into one result with one message per line, and the command splits them
again.

## Struct punning

`StructPunning.ql` reports every cast that turns a pointer to `struct X` into a
pointer to an unrelated `struct Y` (not related by inheritance). The pointer may
flow there through other variables, `void *`, or function calls. FSan reports
field accesses through such pointers as tag mismatches: they are type errors,
not bounds violations. The reported struct types are therefore the candidates
for the FSan blocklist, and developers can review them before a fuzzing
campaign starts.

The message names both structs and where the `struct X` pointer comes from. For
a direct cast, `(struct Y *)x`, that is `x`. Otherwise it is the place where the
pointer was converted to `void *` or another type on its way to the cast, such as
the argument of a `void *` parameter. If there are several such places, the
message names one and counts the others.

On `test/` the query reports one result in `pun.c`:

```
Pointer to struct A (pun.c:5) reinterpreted as struct B (pun.c:6). The struct A pointer comes from a (pun.c:11).
```

It reports nothing on `iob.c`, a plain intra-object overflow with matching types.

`PunnedTypes.ql` condenses this to one result per pair of types, located at the
first cast. Its message is the pair, `"struct A" : "struct B"`, meaning that a
`struct A *` is cast to a `struct B *`. Types are written as in the source:
`struct X`, `union U`, `ns::X` qualified in C++, and an anonymous struct by its
typedef name. To list the pairs:

```bash
jq -r '.runs[].results[] | select(.ruleId == "fsan/punned-types") | .message.text | split("\n")[] | gsub("\\\\(?<c>.)"; .c)' db.sarif | sort -u
```

```
"struct A" : "struct B"
```

For a real project, run `codeql database create` with the project's build
command, then turn these pairs into blocklist entries.

The query covers explicit casts, the common case. It does not see the following:

- punning through `union`s (out of FSan's scope);
- `memcpy` into an object of another type (well-defined in C);
- casts in code that is not compiled into the database.

Expect reports for idioms such as `struct sockaddr` / `struct sockaddr_in`.
These are punning by the letter of the standard, so they belong in the
blocklist too.

Run-time alternative: LLVM's TypeSanitizer (`clang -fsanitize=type`, LLVM ≥ 20)
reports the punned access in `pun.c` ("READ of size 4 ... with type int (in B at
offset 4) accesses an existing object of type float (in A at offset 4)") and is
silent on `iob.c`. Replaying an FSan report's input under TySan therefore tells
a type error from a bounds violation automatically.

## Flattened multidimensional arrays

Both array queries share `FlattenedArrays.qll`. It defines a *flatten point*: an
expression that turns a multidimensional array `T A[N][M]...` into a pointer to
non-array elements (`T *`, `char *`, `void *`). There are three kinds:

| kind | example | row length |
|---|---|---|
| cast | `(int *)A`, `(char *)&A`, `(int *)r` with `int (*r)[3]` | inner dimension |
| row | `int *p = A[i];` (not `A[i][j]` or `*A[i]`) | `M` |
| elem | `&A[i][j]` | `M` |

`FlattenedArrayAccess.ql` follows each flatten point through data flow, across
functions too, to a subscript, pointer arithmetic, `++`/`--` or `+=`/`-=`. Each
result says how sure the query is that the access crosses a row:

- **the whole array is cast to a flat pointer:** the kind is `cast`.
- **constant offset ≥ row length:** for example `p[4]` on a row of 3.
- **loop bound exceeds row length:** the loop condition has a larger constant or a `sizeof`.
- **may cross the row:** none of the above. Row walks such as `r = A[i]; r[j]` with
  `j < M` end up here, and they are fine.

`FlattenedArrayEscape.ql` reports flat pointers that are passed to a function,
returned, stored into a global, field, `*q` or `q[i]`, or used in an
initializer. It skips calls to `mem*` functions (`memset(A, 0, sizeof A)` is
normal), and pointers to rows (`f(A)` with `f(int (*)[3])`).

Neither query follows flow through global variables: otherwise one
`memset(A, ...)` would reach every read of `A`. A flat pointer stored in a global
is still reported as an escape. Neither query sees direct overruns such as
`A[0][5]`, where the subscript itself crosses the row.

## mem* writes past a member

`MemsetOverMember.ql` reports `memset`, `bzero`, `explicit_bzero`, `memcpy` and
`memmove` calls (and their `__builtin_` forms) whose destination is a struct
member (`&s->f`, `s->arr`, `&s->arr[i]`) and whose size is a constant larger than
what is left of the member. `sizeof(*s) - offsetof(struct S, b)` is a constant
too. The message lists the members that the write also covers, and how far it
runs past the end of the struct:

```
memset of 12 bytes at S.b (memset_member.c:6) (4 bytes) also writes c.
memset of 16 bytes at S.b (memset_member.c:6) (4 bytes) also writes c, and 4 bytes past the end of struct S.
```

It does not report writes whose size is not a constant, or members of unions.

## Custom allocators

`Allocators.qll` decides which functions are custom allocators. A function
counts if it returns a pointer and meets one of these conditions:

- **wraps:** it is defined in the project and returns the result of an
  allocation function (`malloc`, `calloc`, `realloc`, `new`, … as modeled by
  CodeQL) or of another custom allocator. For example, `xmalloc` wraps `malloc`.
- **carves:** it returns a pointer derived from a pointer or array field of an
  object, and it also updates a field of that same object. This covers bump
  arenas (`p = a->base + a->used; a->used += n;`) and free lists, also called
  recyclers (`n = r->free; r->free = n->next;`). A getter such as
  `return l->name;` updates nothing, so it does not count.
- **attribute:** it is declared `__attribute__((malloc))` or `alloc_size` and is
  not a known allocation function.

`CustomAllocatorStruct.ql` reports each call to a custom allocator whose result
flows, possibly through variables, into a conversion to a pointer to a struct or
class (not a union). It reports at the outermost allocator call: the `xmalloc`
call inside `xzalloc` is not reported, unless the allocator itself does the
conversion (`struct S *new_s(void) { return xmalloc(sizeof(struct S)); }`).

`ArenaAllocator.ql` reports each allocator that carves, or wraps one that
carves, with the arena's struct type and field. It also reports where the arena
object comes from:

- **static instance:** the allocator uses a global or static object (`R.free`).
  Only that object is reported.
- **allocated by …:** the allocator takes the arena as a pointer (`r->free`).
  Every instantiation of the type is reported: allocation calls (including
  custom allocators) whose result is converted to the struct, `new`, and static
  instances.
- **no instantiation found:** none of the above exists in the database.

The carve rule is a heuristic, so expect some false positives: anything that
returns a pointer from a field and moves it forward, such as a tokenizer
(`t = l->pos; l->pos += len; return t;`) or a queue pop.

Detection misses allocators that return memory through an out-parameter
(`int alloc(void **out)`), arenas whose state lives in local or global scalars
rather than in a struct, and allocators only called through function pointers.
