/**
 * @name mem* write that starts at a struct member and runs past it
 * @description `memset`, `bzero`, `memcpy` or `memmove` writes a constant
 *              number of bytes, starting at a struct member, that is larger
 *              than what is left of the member. The write is in bounds for the
 *              object but crosses into the following members (or past the
 *              struct), which FSan reports as an intra-object overflow.
 * @kind problem
 * @problem.severity warning
 * @id fsan/memset-over-member
 */

import cpp
import Locations

/** `c` writes `size` bytes at `dest`. */
predicate memWrite(Call c, Expr dest, Expr size) {
  exists(string n | n = c.getTarget().getName() |
    n.regexpMatch("(__builtin_)?(memset|memcpy|memmove)|__builtin___(memset|memcpy|memmove)_chk") and
    dest = c.getArgument(0) and
    size = c.getArgument(2)
    or
    n.regexpMatch("(__builtin_)?(explicit_)?bzero") and
    dest = c.getArgument(0) and
    size = c.getArgument(1)
  )
}

/** `dest` points `start` bytes into member `fa`: `&s->f`, `s->arr`, `&s->arr[i]`. */
predicate memberStart(Expr dest, FieldAccess fa, int start) {
  exists(Expr d | d = dest.getUnconverted() |
    fa = d.(AddressOfExpr).getOperand() and start = 0
    or
    fa = d and fa.getUnspecifiedType() instanceof ArrayType and start = 0
    or
    exists(ArrayExpr e | e = d.(AddressOfExpr).getOperand() |
      fa = e.getArrayBase().getUnconverted() and
      start = e.getArrayOffset().getValue().toInt() * e.getUnspecifiedType().getSize()
    )
  )
}

/** The members after `f` that start before byte `to` of its struct, or "no other member". */
bindingset[to]
string covered(Field f, int to) {
  if exists(Field g | g.getDeclaringType() = f.getDeclaringType() and after(f, g, to))
  then
    result =
      concat(Field g | g.getDeclaringType() = f.getDeclaringType() and after(f, g, to) |
        g.getName(), ", " order by g.getByteOffset()
      )
  else result = "no other member"
}

bindingset[to]
private predicate after(Field f, Field g, int to) {
  g.getByteOffset() >= f.getByteOffset() + f.getType().getSize() and g.getByteOffset() < to
}

from
  Call c, Expr dest, Expr size, FieldAccess fa, Field f, Struct s, int start, int n, int end,
  string from_, string past
where
  memWrite(c, dest, size) and
  memberStart(dest, fa, start) and
  f = fa.getTarget() and
  s = f.getDeclaringType() and
  not s instanceof Union and
  n = size.getValue().toInt() and
  n > f.getType().getSize() - start and
  end = f.getByteOffset() + start + n and
  (if start > 0 then from_ = ", from offset " + start else from_ = "") and
  (
    if end > s.getSize()
    then past = ", and " + (end - s.getSize()) + " bytes past the end of struct " + s.getName()
    else past = ""
  )
select c,
  c.getTarget().getName() + " of " + n + " bytes at $@ (" + f.getType().getSize() + " bytes" +
    from_ + ") also writes " + covered(f, end) + past + ".", f,
  withLoc(s.getName() + "." + f.getName(), f)
