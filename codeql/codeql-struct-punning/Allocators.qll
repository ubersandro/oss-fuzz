/**
 * Custom allocators: project functions that hand out memory. Shared by
 * CustomAllocatorStruct.ql and ArenaAllocator.ql.
 */

import cpp
import semmle.code.cpp.dataflow.new.DataFlow
import semmle.code.cpp.dataflow.new.TaintTracking
import semmle.code.cpp.models.interfaces.Allocation

/** `f` (defined in the project) returns the result of call `c`. */
predicate returnsCall(Function f, Call c) {
  f.hasDefinition() and
  exists(ReturnStmt r | r.getEnclosingFunction() = f and DataFlow::localExprFlow(c, r.getExpr()))
}

/** `fa` is written: assigned (also `+=`, ...) or incremented/decremented. */
private predicate written(FieldAccess fa) {
  fa = any(Assignment a).getLValue() or fa = any(CrementOperation c).getOperand()
}

/**
 * `f` hands out memory carved from field `fld` of an arena (or recycler) object
 * `obj` of struct type `arena`: the returned pointer is derived from `obj.fld`,
 * and `f` also updates a field of `obj`. Examples:
 *
 *   bump allocator   `p = a->base + a->used; a->used += n; return p;`
 *   free list        `n = r->free; r->free = n->next; return n;`
 */
predicate carves(Function f, Struct arena, Field fld, Variable obj) {
  not arena instanceof Union and
  exists(ReturnStmt r, FieldAccess read, FieldAccess write |
    r.getEnclosingFunction() = f and
    read.getEnclosingFunction() = f and
    TaintTracking::localTaint(DataFlow::exprNode(read), DataFlow::exprNode(r.getExpr())) and
    fld = read.getTarget() and
    fld.getUnspecifiedType() instanceof DerivedType and // pointer or array: the memory itself
    arena = fld.getDeclaringType() and
    obj = read.getQualifier().(VariableAccess).getTarget() and
    write.getEnclosingFunction() = f and
    written(write) and
    write.getTarget().getDeclaringType() = arena and
    write.getQualifier().(VariableAccess).getTarget() = obj
  )
}

/**
 * `f` is a custom allocator, for the reason `why`:
 *
 *   - it returns the result of an allocation function or of another custom
 *     allocator (`xmalloc` wraps `malloc`);
 *   - it carves memory from an arena or recycler object (see `carves`);
 *   - it is declared `__attribute__((malloc))` or `alloc_size` and is not a
 *     known allocation function.
 */
predicate customAllocator(Function f, string why) {
  f.getUnspecifiedType() instanceof PointerType and
  (
    exists(Call a | returnsCall(f, a) |
      a instanceof AllocationExpr and why = "wraps " + a.getTarget().getName()
      or
      customAllocator(a.getTarget(), _) and why = "wraps " + a.getTarget().getName()
    )
    or
    exists(Struct arena, Field fld | carves(f, arena, fld, _) |
      why = "carves from " + arena.getName() + "." + fld.getName()
    )
    or
    not f instanceof AllocationFunction and
    exists(string attr | attr = f.getAnAttribute().getName() and attr = ["malloc", "alloc_size"] |
      why = "__attribute__((" + attr + "))"
    )
  )
}

/** All reasons why `f` is a custom allocator, comma-separated. */
string allocatorReasons(Function f) { result = concat(string w | customAllocator(f, w) | w, ", ") }

/** `t` points to a struct or class (not a union). */
predicate pointsToStruct(Type t, Class s) {
  s = t.getUnspecifiedType().(PointerType).getBaseType().getUnspecifiedType() and
  not s instanceof Union
}

module AllocConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node n) { customAllocator(n.asExpr().(Call).getTarget(), _) }

  // the operand without conversions: `(OP *)(slab = new_slab(n))` converts a parenthesis
  predicate isSink(DataFlow::Node n) {
    exists(Cast c | n.asExpr() = c.getExpr().getUnconverted() and pointsToStruct(c.getType(), _))
  }
}

module Alloc = DataFlow::Global<AllocConfig>;

/**
 * The result of `call`, a call to a custom allocator, flows into `c`, a
 * conversion to a pointer to struct `s`. `call` is the outermost allocator
 * call: the `xmalloc` call inside `xzalloc` does not count, unless the
 * allocator itself converts (`struct S *new_s(void) { return xmalloc(sizeof(struct S)); }`).
 */
predicate allocatorResult(Call call, Cast c, Class s) {
  exists(DataFlow::Node source, DataFlow::Node sink |
    Alloc::flow(source, sink) and
    call = source.asExpr() and
    sink.asExpr() = c.getExpr().getUnconverted() and
    pointsToStruct(c.getType(), s)
  ) and
  (
    not customAllocator(call.getEnclosingFunction(), _) or
    c.getEnclosingFunction() = call.getEnclosingFunction()
  )
}
