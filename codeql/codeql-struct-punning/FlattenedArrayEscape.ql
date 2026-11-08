/**
 * @name Flat pointer into a multidimensional array escapes
 * @description A pointer into a multidimensional array (`(int *)A`, `&A[0][0]`,
 *              `A[i]`) is passed to a function, returned, or stored outside a
 *              local variable. The code that uses it no longer sees the array's
 *              shape, so its accesses may cross rows.
 * @kind problem
 * @problem.severity warning
 * @id fsan/flattened-array-escape
 */

import cpp
import FlattenedArrays

/** mem* functions access the object bytewise; they are FSan's business, not this query's. */
predicate memFunction(Function f) {
  f.getName().regexpMatch("(__builtin_)?(memset|memcpy|memmove|memcmp|bzero|bcopy)(_chk)?")
}

/** Storing into `lhs` makes the value outlive the local scope (global, field, `*q`, `q[i]`). */
predicate nonLocal(Expr lhs) {
  lhs.(VariableAccess).getTarget() instanceof GlobalOrNamespaceVariable
  or
  lhs.(VariableAccess).getTarget().(LocalVariable).isStatic()
  or
  lhs instanceof FieldAccess
  or
  lhs instanceof PointerDereferenceExpr
  or
  lhs instanceof ArrayExpr
}

predicate escapes(DataFlow::Node n, Element site, string how) {
  exists(Call c, int i |
    FlattenSource::isExpr(n, c.getArgument(i)) and
    not memFunction(c.getTarget()) and
    site = c and
    how = "passed to " + c.getTarget().getName() + "()"
  )
  or
  exists(ReturnStmt r |
    FlattenSource::isExpr(n, r.getExpr()) and
    site = r and
    how = "returned from " + r.getEnclosingFunction().getName() + "()"
  )
  or
  exists(AssignExpr a |
    FlattenSource::isExpr(n, a.getRValue()) and
    nonLocal(a.getLValue()) and
    site = a and
    if a.getLValue() instanceof FieldAccess
    then how = "stored into field " + a.getLValue().(FieldAccess).getTarget().getName()
    else how = "stored into " + a.getLValue().toString()
  )
  or
  exists(AggregateLiteral l |
    FlattenSource::isExpr(n, l.getAChild()) and
    site = l and
    how = "stored in an initializer"
  )
}

module EscapeConfig implements DataFlow::ConfigSig {
  predicate isSource = FlattenSource::isSource/1;

  predicate isBarrier = FlattenSource::isBarrier/1;

  predicate isSink(DataFlow::Node n) { escapes(n, _, _) }
}

module Escape = DataFlow::Global<EscapeConfig>;

from FlattenPoint src, Element site, string how
where
  exists(DataFlow::Node source, DataFlow::Node sink |
    Escape::flow(source, sink) and src = FlattenSource::pointOf(source) and escapes(sink, site, how)
  )
  or
  // file-scope initializers (`int *gp = &A[0][0];`) have no data flow
  exists(GlobalOrNamespaceVariable v |
    src.getParent*() = v.getInitializer().getExpr() and
    site = src and
    how = "stored into global " + v.getName()
  )
select site, "Flat pointer to " + src.describe() + " from $@ " + how + ".", src,
  withLoc(src.label(), src)
