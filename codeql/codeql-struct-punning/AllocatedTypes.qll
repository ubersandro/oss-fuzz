/**
 * The struct type of the memory that a custom allocator returns: the type of
 * the allocation or static object that the returned pointer points into. FSan
 * tags heap memory with the type it finds at the libc allocation, so this is
 * the layout in shadow memory, whatever type the caller converts the result
 * to. Used by AllocatorPunning.ql.
 */

import cpp
import Allocators
private import Punning as P

/** `t`, or the innermost element type if `t` is an array, as a struct or class (not a union). */
private Class structOf(Type t) {
  if t.getUnspecifiedType() instanceof ArrayType
  then result = structOf(t.getUnspecifiedType().(ArrayType).getBaseType())
  else (
    result = t.getUnspecifiedType() and not result instanceof Union
  )
}

/**
 * The pointer to the object that `lv` is a sub-object of (`s` in `s->f`,
 * `a` in `a[i]`), or `lv`'s own variable if it names one (`P` in `P.buf`).
 */
private Expr lvalueBase(Expr lv) {
  result = lv.(PointerFieldAccess).getQualifier().getFullyConverted()
  or
  result = lvalueBase(lv.(DotFieldAccess).getQualifier())
  or
  result = lv.(ArrayExpr).getArrayBase().getFullyConverted()
  or
  result = lv.(PointerDereferenceExpr).getOperand().getFullyConverted()
  or
  result = lv and
  lv instanceof VariableAccess and
  not lv instanceof FieldAccess and
  not lv.getUnspecifiedType() instanceof PointerType
}

/** `e` points to the sub-object `lv`: `&s->f`, `&a[i]`, or an array member `s->buf` that decays. */
private predicate subObject(Expr e, Expr lv) {
  lv = e.(AddressOfExpr).getOperand()
  or
  e = lv and lv.(FieldAccess).getUnspecifiedType() instanceof ArrayType
}

/** `fld` is a member that `lv` selects: `f` in `s->f`, `f` and `g` in `s->f.g`. */
private predicate selects(Expr lv, Field fld) {
  fld = lv.(FieldAccess).getTarget() or selects(lv.(DotFieldAccess).getQualifier(), fld)
}

/**
 * The pointer `e` is derived from `src`: it points into the object that
 * `src` points to, or into one of its sub-objects. Pointers stored in
 * variables and fields come from every value assigned to them, in any object
 * of the type (`r->cur` from `r->cur = r->mem`).
 */
private predicate derivedFrom(Expr e, Expr src) {
  src = e.(Conversion).getExpr()
  or
  (e instanceof PointerAddExpr or e instanceof PointerSubExpr) and
  src = e.(BinaryOperation).getAnOperand().getFullyConverted() and
  src.getUnspecifiedType() instanceof PointerType
  or
  exists(Expr lv | subObject(e, lv) and src = lvalueBase(lv))
  or
  exists(ConditionalExpr c | c = e | src = [c.getThen(), c.getElse()].getFullyConverted())
  or
  src = e.(AssignExpr).getRValue().getFullyConverted()
  or
  src = e.(CommaExpr).getRightOperand().getFullyConverted()
  or
  exists(Variable v |
    v = e.(VariableAccess).getTarget() and v.getUnspecifiedType() instanceof PointerType
  |
    src = v.getAnAssignedValue().getFullyConverted()
  )
}

/** `c` calls a custom allocator that is not a known allocation function: `xmalloc(n)`. */
private predicate wrapped(Call c) {
  customAllocator(c.getTarget(), _) and not c instanceof AllocationExpr
}

/** `e` is on the way to a pointer that the custom allocator `f` returns, without entering wrapped allocators. */
private predicate returned(Function f, Expr e) {
  customAllocator(f, _) and
  e = any(ReturnStmt r | r.getEnclosingFunction() = f).getExpr().getFullyConverted()
  or
  exists(Expr next | returned(f, next) and derivedFrom(next, e))
}

/** The struct that allocation `a` creates: what its result is converted to, else what it takes the `sizeof` of. */
private Class allocationType(AllocationExpr a) {
  if exists(structOf(a.getAllocatedElementType()))
  then result = structOf(a.getAllocatedElementType())
  else
    exists(SizeofOperator s | s.getParent+() = a |
      result =
        structOf([
            s.(SizeofTypeOperator).getTypeOperand(),
            s.(SizeofExprOperator).getExprOperand().getType()
          ])
    )
}

/**
 * `origin` creates memory of struct `m`: an allocation, or a declared object
 * or array (`static struct pool P;`).
 */
private predicate memoryOrigin(Expr origin, Class m, string how) {
  m = allocationType(origin) and
  (
    if origin instanceof Call
    then how = "allocated by " + origin.(Call).getTarget().getName() + "()"
    else how = "allocated by new"
  )
  or
  exists(Variable v |
    v = origin.(VariableAccess).getTarget() and
    not origin instanceof FieldAccess and
    m = structOf(v.getType())
  |
    if v instanceof LocalScopeVariable and not v.isStatic()
    then how = "local variable " + v.getName()
    else how = "static object " + v.getName()
  )
}

/** Where the memory of `origin` is created: the allocation, or the declaration of the object. */
Element originSite(Expr origin) {
  memoryOrigin(origin, _, _) and
  if origin instanceof VariableAccess
  then result = origin.(VariableAccess).getTarget()
  else result = origin
}

/**
 * Allocator `f` returns memory of struct `m` that comes from `origin`, as
 * `how` says, directly or through the allocators it wraps.
 */
predicate allocatedType(Function f, Class m, Expr origin, string how) {
  returned(f, origin) and memoryOrigin(origin, m, how)
  or
  exists(Call c | returned(f, c) and wrapped(c) and allocatedType(c.getTarget(), m, origin, how))
}

/** `e` lies between `start` (an origin or a wrapped allocator call) and a return of `f`. */
private predicate between(Function f, Expr start, Expr e) {
  returned(f, start) and
  (memoryOrigin(start, _, _) or wrapped(start)) and
  e = start
  or
  exists(Expr prev | between(f, start, prev) and derivedFrom(e, prev) and returned(f, e))
}

/** In `f`, the pointer derived from `start` is narrowed to the member `fld` (`&slot->opslot_op`). */
private predicate narrowedTo(Function f, Expr start, Field fld) {
  exists(Expr e, Expr lv | between(f, start, e) and subObject(e, lv) and selects(lv, fld))
}

/**
 * The memory that `f` returns from `origin` is a sub-object: the pointer is
 * narrowed to the member `fld` on the way, in `f` or in an allocator it wraps.
 */
predicate throughField(Function f, Expr origin, Field fld) {
  allocatedType(f, _, origin, _) and narrowedTo(f, origin, fld)
  or
  exists(Call c | returned(f, c) and wrapped(c) and allocatedType(c.getTarget(), _, origin, _) |
    throughField(c.getTarget(), origin, fld) or narrowedTo(f, c, fld)
  )
}

/** `c` as the source spells it: `struct A`, `class ns::B`, or the typedef name of an anonymous struct. */
string className(Class c) {
  result = P::typeName(c)
  or
  not c instanceof Struct and result = "class " + c.getQualifiedName()
}

/** `a` and `b` are related by inheritance (C++), so using one as the other is not punning. */
predicate relatedClasses(Class a, Class b) { a.getABaseClass+() = b or b.getABaseClass+() = a }
