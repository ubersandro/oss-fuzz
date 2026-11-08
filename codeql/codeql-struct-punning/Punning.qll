/**
 * Struct type punning: a pointer to one struct type that flows into a cast to a
 * pointer to an unrelated struct type. Shared by StructPunning.ql (every cast)
 * and PunnedTypes.ql (every pair of types).
 */

import cpp
import semmle.code.cpp.dataflow.new.DataFlow

/** `t` is a pointer to struct `s` (ignoring typedefs and cv-qualifiers). */
predicate pointsToStruct(Type t, Struct s) {
  t.getUnspecifiedType().(PointerType).getBaseType().getUnspecifiedType() = s
}

/** `s` as the source spells it: `struct A`, `union U`, or the typedef name of an anonymous struct. */
string typeName(Struct s) {
  if s.isAnonymous() and exists(TypedefType t | t.getUnderlyingType() = s)
  then result = min(TypedefType t | t.getUnderlyingType() = s | t.getName())
  else
    if s instanceof Union
    then result = "union " + s.getQualifiedName()
    else result = "struct " + s.getQualifiedName()
}

/** `a` and `b` are related by inheritance (C++), so the cast is not punning. */
predicate related(Struct a, Struct b) { a.getABaseClass+() = b or b.getABaseClass+() = a }

module PunConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node n) { pointsToStruct(n.asExpr().getType(), _) }

  predicate isSink(DataFlow::Node n) {
    exists(Cast c | n.asExpr() = c.getExpr() and pointsToStruct(c.getType(), _))
  }
}

module Pun = DataFlow::Global<PunConfig>;

/** `e` is a `struct s *` converted to another type on the spot: `void *v = a;`, `f(a)` with `f(void *)`. */
predicate convertedAway(Expr e, Struct s) {
  pointsToStruct(e.getType(), s) and not pointsToStruct(e.getFullyConverted().getType(), s)
}

/**
 * Where the `struct fromT *` that `c` reinterprets comes from: the operand of
 * `c` if it is a `struct fromT *` (`(struct B *)a`); otherwise each place where
 * such a pointer is converted to another type on its way to `c` (`void *v = a;`),
 * or, if there is none because the pointer changes type in memory (through a
 * `void **`), each `struct fromT *` that flows to `c`.
 */
Expr origin(Cast c, Struct fromT) {
  exists(DataFlow::Node sink |
    sink.asExpr() = c.getExpr() and
    exists(DataFlow::Node src | Pun::flow(src, sink) and pointsToStruct(src.asExpr().getType(), fromT))
  |
    result = c.getExpr() and pointsToStruct(result.getType(), fromT)
    or
    not pointsToStruct(c.getExpr().getType(), fromT) and
    exists(DataFlow::Node src | Pun::flow(src, sink) and result = src.asExpr() |
      convertedAway(result, fromT)
      or
      pointsToStruct(result.getType(), fromT) and
      not exists(DataFlow::Node o | Pun::flow(o, sink) and convertedAway(o.asExpr(), fromT))
    )
  )
}

/** `c` reinterprets a pointer to `fromT` as a pointer to the unrelated struct `toT`. */
predicate punning(Cast c, Struct fromT, Struct toT) {
  pointsToStruct(c.getType(), toT) and
  exists(origin(c, fromT)) and
  fromT != toT and
  not related(fromT, toT)
}
