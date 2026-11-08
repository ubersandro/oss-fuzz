/**
 * @name Multidimensional array traversed as a flat array
 * @description A pointer into a multidimensional array (`(int *)A`, `&A[0][0]`,
 *              `A[i]`) is advanced or indexed. If it crosses a row, FSan reports
 *              an out-of-bounds access within the array (the bounds are the
 *              row's), although the access stays inside the object.
 * @kind problem
 * @problem.severity warning
 * @id fsan/flattened-array-access
 */

import cpp
import FlattenedArrays

/** `e` moves pointer `p` or reads at an offset from it. */
predicate moves(Expr p, Expr e) {
  p = e.(ArrayExpr).getArrayBase() and not p.getUnspecifiedType() instanceof ArrayType
  or
  p = e.(PointerArithmeticOperation).getAnOperand() and p.getUnspecifiedType() instanceof PointerType
  or
  p = e.(CrementOperation).getOperand()
  or
  p = e.(AssignPointerAddExpr).getLValue()
  or
  p = e.(AssignPointerSubExpr).getLValue()
}

module FlatConfig implements DataFlow::ConfigSig {
  predicate isSource = FlattenSource::isSource/1;

  predicate isBarrier = FlattenSource::isBarrier/1;

  predicate isSink(DataFlow::Node n) { exists(Expr p | moves(p, _) | FlattenSource::isExpr(n, p)) }
}

module Flat = DataFlow::Global<FlatConfig>;

/** The constant offset of `e` from the pointer, if any. */
int constOffset(Expr e) {
  result = e.(ArrayExpr).getArrayOffset().getValue().toInt()
  or
  result = e.(PointerAddExpr).getAnOperand().getValue().toInt()
}

/** A loop around `e` compares against a constant larger than `n`, or a `sizeof`. */
bindingset[n]
predicate loopBoundExceeds(Expr e, int n) {
  exists(Loop l, Expr k |
    (e.getEnclosingStmt().getParentStmt*() = l.getStmt() or e.getParent*() = l.getCondition()) and
    k = l.getCondition().getAChild*()
  |
    k.getValue().toInt() > n or k instanceof SizeofOperator
  )
}

string verdict(FlattenPoint src, Expr access) {
  if src.getKind() = "cast"
  then result = "the whole array is cast to a flat pointer"
  else
    if constOffset(access) >= src.getRowLength()
    then result = "constant offset " + constOffset(access) + " >= row length " + src.getRowLength()
    else
      if loopBoundExceeds(access, src.getRowLength())
      then result = "loop bound exceeds row length " + src.getRowLength()
      else result = "may cross the row (length " + src.getRowLength() + ")"
}

from DataFlow::Node source, DataFlow::Node sink, FlattenPoint src, Expr p, Expr access
where
  Flat::flow(source, sink) and
  src = FlattenSource::pointOf(source) and
  moves(p, access) and
  FlattenSource::isExpr(sink, p)
select access,
  "Flat access to " + src.describe() + " through the pointer from $@: " + verdict(src, access) + ".",
  src, withLoc(src.label(), src)
