/**
 * Points where a multidimensional array `T A[N][M]...` is turned into a pointer
 * to scalars, i.e. viewed as one flat array. Shared by FlattenedArrayAccess.ql
 * and FlattenedArrayEscape.ql.
 */

import cpp
import semmle.code.cpp.dataflow.new.DataFlow
import Locations

/** An array whose elements are arrays: `T A[N][M]`, `T A[N][M][K]`, ... */
class MultiDimArrayType extends ArrayType {
  MultiDimArrayType() { this.getBaseType().getUnspecifiedType() instanceof ArrayType }
}

/** `t` points to something that is not an array (an element, `char` or `void`). */
private predicate flatPointer(Type t) {
  exists(PointerType p | p = t.getUnspecifiedType() |
    not p.getBaseType().getUnspecifiedType() instanceof ArrayType
  )
}

/** `e` designates an array that is itself an element of another array (a row). */
private predicate isRow(Expr e) {
  e.getUnspecifiedType() instanceof ArrayType and
  (e instanceof ArrayExpr or e instanceof PointerDereferenceExpr)
}

/** The variable or field whose storage `e` designates. */
Variable rootVariable(Expr e) {
  result = e.(VariableAccess).getTarget()
  or
  result = rootVariable(e.(Conversion).getExpr())
  or
  result = rootVariable(e.(ArrayExpr).getArrayBase())
  or
  result = rootVariable(e.(AddressOfExpr).getOperand())
  or
  result = rootVariable(e.(PointerDereferenceExpr).getOperand())
}

/**
 * An expression that yields a flat pointer into a multidimensional array:
 *
 *   cast   `(int *)A`, `(int *)&A`, `(char *)r` with `int (*r)[3]`
 *   row    `A[i]` decaying to `int *`, unless subscripted or dereferenced at once
 *   elem   `&A[i][j]`
 */
class FlattenPoint extends Expr {
  string kind;
  int rowLength;

  FlattenPoint() {
    flatPointer(this.getType()) and
    (
      exists(Expr u | u = this.(Cast).getExpr().getUnconverted() |
        kind = "cast" and
        (
          rowLength = u.getUnspecifiedType().(MultiDimArrayType).getBaseType().getUnspecifiedType().(ArrayType).getArraySize()
          or
          exists(ArrayType pointee |
            pointee = u.getUnspecifiedType().(PointerType).getBaseType().getUnspecifiedType()
          |
            rowLength = pointee.(MultiDimArrayType).getBaseType().getUnspecifiedType().(ArrayType).getArraySize()
            or
            // `int (*r)[M]`: a pointer to rows, unless it is `&B` for a 1-D `B`
            not pointee instanceof MultiDimArrayType and
            not u.(AddressOfExpr).getOperand() instanceof VariableAccess and
            rowLength = pointee.getArraySize()
          )
        )
      )
      or
      exists(ArrayToPointerConversion c | c = this |
        isRow(c.getExpr()) and
        not exists(ArrayExpr a | a.getArrayBase().getFullyConverted() = c) and
        not exists(PointerDereferenceExpr d | d.getOperand().getFullyConverted() = c) and
        kind = "row" and
        rowLength = c.getExpr().getUnspecifiedType().(ArrayType).getArraySize()
      )
      or
      exists(ArrayExpr elem, Expr row |
        elem = this.(AddressOfExpr).getOperand() and
        row = elem.getArrayBase().getUnconverted() and
        isRow(row) and
        kind = "elem" and
        rowLength = row.getUnspecifiedType().(ArrayType).getArraySize()
      )
    )
  }

  /** `cast`, `row` or `elem`, see the class comment. */
  string getKind() { result = kind }

  /** Number of elements in the row the pointer starts in. */
  int getRowLength() { result = rowLength }

  /** The multidimensional array (variable or field), if it is named. */
  Variable getArray() { result = rootVariable(this) }

  /** Human-readable name of the flattened array, with where it is declared. */
  string describe() {
    if exists(this.getArray())
    then
      exists(Variable v, string at | v = this.getArray() |
        (if exists(loc(v)) then at = ", " + loc(v) else at = "") and
        result = "'" + v.getName() + "' (" + v.getType().toString() + at + ")"
      )
    else result = "a multidimensional array"
  }

  /** What the flatten point is, for messages: `cast to int *`, `row used as int *` or `address of an element`. */
  string label() {
    kind = "cast" and result = "cast to " + this.getType().toString()
    or
    kind = "row" and result = "row used as " + this.getType().toString()
    or
    kind = "elem" and result = "address of an element"
  }
}

module FlattenSource {
  /** The flatten point at `n` (most are conversions, which `asExpr` skips). */
  FlattenPoint pointOf(DataFlow::Node n) { result = [n.asExpr(), n.asConvertedExpr()] }

  predicate isSource(DataFlow::Node n) { exists(pointOf(n)) }

  /**
   * Flow through a global variable is not followed: writing into a global
   * array (e.g. `memset(A, ...)`) would otherwise reach every read of `A`.
   * Storing a flat pointer in a global is reported by FlattenedArrayEscape.ql.
   */
  predicate isBarrier(DataFlow::Node n) { n instanceof DataFlow::VariableNode }

  /** `n` is the value of `e`, before or after its conversions. */
  predicate isExpr(DataFlow::Node n, Expr e) {
    n.asExpr() = e or n.asConvertedExpr() = e.getFullyConverted()
  }
}
