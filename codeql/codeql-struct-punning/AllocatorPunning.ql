/**
 * @name Custom allocator memory used as another struct
 * @description A custom allocator (see Allocators.qll) returns memory of one
 *              struct type: the type of the allocation or static object it
 *              hands out, which FSan tags. Its caller converts the result to a
 *              pointer to an unrelated struct type, so FSan reports field
 *              accesses through it as tag mismatches. The allocated type is
 *              the blocklist candidate. One result per allocator, allocated
 *              type and converted-to type, at the first conversion.
 * @kind problem
 * @problem.severity warning
 * @id fsan/allocator-punning
 */

import cpp
import AllocatedTypes
import Locations

/** `n` places, as a suffix: "", " and in 1 other place", " and in 3 other places". */
bindingset[n]
string others(int n) {
  n = 0 and result = ""
  or
  n = 1 and result = " and in 1 other place"
  or
  n > 1 and result = " and in " + n + " other places"
}

/** `f`'s result is converted to `t` at `c`. */
predicate convertedTo(Function f, Class t, Cast c) {
  exists(Call call | allocatorResult(call, c, t) and f = call.getTarget())
}

/** `f` returns memory of struct `m` created at `site` (an allocation or a declaration), as `how` says. */
predicate allocatedAt(Function f, Class m, Element site, string how) {
  exists(Expr o | allocatedType(f, m, o, how) and site = originSite(o))
}

from Function f, Class m, Class t, Cast c, Element site, string how, string fields, string narrowed
where
  convertedTo(f, t, _) and
  allocatedType(f, m, _, _) and
  m != t and
  not relatedClasses(m, t) and
  // the first conversion and the first site; the message counts the others
  c =
    min(Cast k |
      convertedTo(f, t, k)
    |
      k
      order by
        k.getLocation().getFile().getAbsolutePath(), k.getLocation().getStartLine(),
        k.getLocation().getStartColumn()
    ) and
  site =
    min(Element s |
      allocatedAt(f, m, s, _)
    |
      s
      order by
        s.getLocation().getFile().getAbsolutePath(), s.getLocation().getStartLine(),
        s.getLocation().getStartColumn()
    ) and
  allocatedAt(f, m, site, how) and
  fields =
    concat(string s |
      exists(Field fld, Expr o |
        allocatedType(f, m, o, _) and
        throughField(f, o, fld) and
        s = fld.getDeclaringType().getName() + "." + fld.getName()
      )
    |
      s, ", "
    ) and
  (if fields = "" then narrowed = "" else narrowed = ", narrowed to " + fields)
select c,
  "Custom allocator $@ returns memory of $@, $@" +
    others(count(Element s | allocatedAt(f, m, s, _)) - 1) + narrowed +
    ". It is converted here to $@" + others(count(Cast k | convertedTo(f, t, k)) - 1) + ".", f,
  withLoc(f.getName(), f), m, withLoc(className(m), m), site, withLoc(how, site), t,
  withLoc(className(t), t)
