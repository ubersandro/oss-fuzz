/**
 * @name Allocated types of custom allocators, as FSan blocklist entries
 * @description One result per custom allocator (see Allocators.qll) and struct
 *              type to blocklist, when the memory that the allocator returns
 *              (see AllocatedTypes.qll) is used as a struct type whose layout
 *              FSan tags differently. The message is one line: the type as an
 *              FSan blocklist entry, the allocator, where the memory is
 *              created, the members that the allocator narrows the pointer
 *              to, and the types that the memory is used as.
 * @kind problem
 * @problem.severity recommendation
 * @id fsan/allocator-types
 */

import cpp
import AllocatedTypes
import Locations

/** `c` converts a pointer of another type to a pointer to struct `t`. */
predicate convertsTo(Cast c, Class t) {
  pointsToStruct(c.getType(), t) and not pointsToStruct(c.getExpr().getType(), t)
}

/**
 * The result of `f` is used as a pointer to struct `t`: `f` converts the
 * pointer that it returns (`return (Bigint *)pmem_next;`), or a call converts
 * the result, at the call or through local variables
 * (`(LISTOP *)Perl_Slab_Alloc(...)`, `struct foo *f = obj_alloc();`). Flow
 * through memory is left out, as any pointer stored in a field or a union can
 * reach casts to any type there.
 */
predicate usedAs(Function f, Class t) {
  // data flow has no node for the conversion itself, so it starts at the operand
  exists(Cast c, ReturnStmt r |
    r.getEnclosingFunction() = f and
    convertsTo(c, t) and
    (
      DataFlow::localExprFlow(c.getExpr().getUnconverted(), r.getExpr())
      or
      c = r.getExpr().getConversion+()
    )
  )
  or
  exists(Call call, Cast c |
    call.getTarget() = f and
    DataFlow::localExprFlow(call, c.getExpr().getUnconverted()) and
    convertsTo(c, t)
  )
}

/**
 * FSan tags the memory that `origin` creates with its type: a call to one of
 * the allocation functions that FSan's front end types (`allocFunctions` in
 * clang/lib/CodeGen/fsan.h), `new`, or a declared object.
 */
predicate fsanTyped(Expr origin) {
  origin.(Call).getTarget().getName() = ["malloc", "calloc", "realloc", "reallocarray"]
  or
  origin instanceof NewOrNewArrayExpr
  or
  origin instanceof VariableAccess
}

/**
 * The fields of `small` are the first fields of `big`, at the same offsets and
 * of the same sizes, as with a C "base struct": FSan gives those bytes the same
 * tags in both types, so using one as the other raises no report.
 */
predicate layoutPrefix(Class small, Class big) {
  small != big and
  forex(Field fs | fs.getDeclaringType() = small |
    exists(Field fb |
      fb.getDeclaringType() = big and
      fb.getInitializationOrder() = fs.getInitializationOrder() and
      fb.getByteOffset() = fs.getByteOffset() and
      fb.getUnspecifiedType().getSize() = fs.getUnspecifiedType().getSize()
    )
  )
}

/** Memory of type `m` used as type `t` raises FSan reports. */
predicate punned(Class m, Class t) {
  m != t and
  not relatedClasses(m, t) and
  not layoutPrefix(m, t) and
  not layoutPrefix(t, m)
}

/**
 * `f` carves the memory that it returns from `origin` out of the array member
 * `fld`, its storage: `P.buf`, `_PyRuntime.dtoa.preallocated`.
 */
predicate storage(Function f, Expr origin, Field fld) {
  throughField(f, origin, fld) and fld.getUnspecifiedType() instanceof ArrayType
}

/** The innermost element type of the array type `t`, as a struct or class (not a union). */
Class elementStruct(Type t) {
  if t.getUnspecifiedType() instanceof ArrayType
  then result = elementStruct(t.getUnspecifiedType().(ArrayType).getBaseType())
  else (
    result = t.getUnspecifiedType() and not result instanceof Union
  )
}

/**
 * Storage `fld` used as struct `t` raises FSan reports. FSan tags it with its
 * elements' layout, or with the member's tag if they are not structs
 * (`char buf[]`), which no struct matches.
 */
predicate storagePunned(Field fld, Class t) {
  punned(elementStruct(fld.getType()), t)
  or
  not exists(elementStruct(fld.getType())) and t != fld.getDeclaringType()
}

/**
 * The memory that `f` returns from `origin`, of type `m`, raises FSan reports
 * when it is used as `t`: storage as `storagePunned` says, other memory if `t`
 * has another layout than `m`.
 */
predicate punnedAs(Function f, Class m, Expr origin, Class t) {
  allocatedType(f, m, origin, _) and
  usedAs(f, t) and
  if storage(f, origin, _)
  then exists(Field fld | storage(f, origin, fld) | storagePunned(fld, t))
  else punned(m, t)
}

/**
 * `f` carves memory out of the array member `fld` of an `arena` object, itself
 * or through the allocators it wraps, whatever the object (`p->mem + p->used`
 * with a parameter `p`): its type is the blocklist candidate even where
 * AllocatedTypes.qll finds no origin.
 */
predicate carvesStorage(Function f, Class arena, Field fld) {
  carves(f, arena, fld, _) and fld.getUnspecifiedType() instanceof ArrayType
  or
  exists(Call c | returnsCall(f, c) and carvesStorage(c.getTarget(), arena, fld))
}

/** `f` carves the storage `fld` of struct `b`, used as struct `t`, which raises FSan reports. */
predicate storageCandidate(Function f, Class b, Field fld, Class t) {
  carvesStorage(f, b, fld) and usedAs(f, t) and storagePunned(fld, t)
}

/**
 * `f` hands out memory from `origin`, which FSan tags, and it is used as the
 * struct `t`, which raises FSan reports. `b` is the type to blocklist: the
 * struct that declares the storage (`struct _dtoa_state`, not the whole
 * runtime state), or else the allocated type. A declared object counts only if
 * `f` carves storage out of it: a function that returns the object itself
 * (`&PL_sv_undef`) does not allocate it.
 */
predicate candidate(Function f, Class b, Expr origin, Class t) {
  exists(Class m |
    allocatedType(f, m, origin, _) and
    fsanTyped(origin) and
    (not origin instanceof VariableAccess or storage(f, origin, _)) and
    punnedAs(f, m, origin, t) and
    if storage(f, origin, _)
    then b = any(Field fld | storage(f, origin, fld)).getDeclaringType()
    else b = m
  )
}

/** The kind that clang writes before a record's IR type name. */
string recordKind(Class c) {
  if c instanceof Union
  then result = "union"
  else
    if c instanceof Struct
    then result = "struct"
    else result = "class"
}

/** `c`'s name, or the typedef name of an anonymous struct. */
string recordName(Class c) {
  if c.isAnonymous() and exists(TypedefType t | t.getUnderlyingType() = c)
  then result = min(TypedefType t | t.getUnderlyingType() = c | t.getQualifiedName())
  else result = c.getQualifiedName()
}

/**
 * The FSan blocklist entry for `c`: its IR type name, as clang spells it
 * (`struct.opslab`, `class.ns::C`, an anonymous struct after its typedef),
 * without template arguments. FSan matches struct entries as prefixes, so the
 * entry covers every instantiation of a template.
 */
string blocklistEntry(Class c) {
  result = recordKind(c) + "." + recordName(c).regexpReplaceAll("<.*>$", "")
}

/** `how` from AllocatedTypes.qll, short: `calloc()`, `new`, `static P`, `local x`. */
bindingset[how]
string shortHow(string how) {
  result =
    how.regexpReplaceAll("^allocated by ", "")
        .regexpReplaceAll("^static object ", "static ")
        .regexpReplaceAll("^local variable ", "local ")
}

/**
 * `f` allocates memory of type `b`: it wraps an allocator, is declared as one,
 * or carves from an object of type `b`. A function that only carves from
 * another struct, such as Perl's `pp_return` moving `cx->blk_sub.retop` on,
 * reaches `b` only through what that pointer may hold.
 */
predicate allocatorOf(Function f, Class b) {
  exists(string why | customAllocator(f, why) and not why.matches("carves from %"))
  or
  carves(f, b, _, _)
}

/**
 * Functions with the same name and location are one result: CodeQL keeps one
 * per translation unit when they differ (perlbench builds regcomp.c twice).
 */
predicate row(string entry, string name, string location, Function f, Class b) {
  (candidate(f, b, _, _) or storageCandidate(f, b, _, _)) and
  allocatorOf(f, b) and
  entry = blocklistEntry(b) and
  name = f.getName() and
  location = loc(f)
}

bindingset[entry, name, location]
string origins(string entry, string name, string location) {
  result =
    concat(string s |
      exists(Function f, Class b, Expr o, string how |
        row(entry, name, location, f, b) and
        candidate(f, b, o, _) and
        allocatedType(f, _, o, how) and
        s = shortHow(how) + " " + loc(originSite(o))
      )
    |
      s, ", "
    )
}

bindingset[entry, name, location]
string members(string entry, string name, string location) {
  result =
    concat(string s |
      exists(Function f, Class b, Field fld |
        row(entry, name, location, f, b) and
        (
          exists(Expr o | candidate(f, b, o, _) and throughField(f, o, fld))
          or
          storageCandidate(f, b, fld, _)
        ) and
        s = recordName(fld.getDeclaringType()) + "." + fld.getName()
      )
    |
      s, ", "
    )
}

predicate usedAsName(string entry, string name, string location, string t) {
  exists(Function f, Class b, Class u |
    row(entry, name, location, f, b) and
    (candidate(f, b, _, u) or storageCandidate(f, b, _, u)) and
    t = className(u)
  )
}

/** The first three types that the memory is used as, and how many others. */
bindingset[entry, name, location]
string usedAsList(string entry, string name, string location) {
  exists(int n | n = count(string t | usedAsName(entry, name, location, t)) |
    result =
      concat(int i, string t |
          i in [1 .. 3] and
          t = rank[i](string u | usedAsName(entry, name, location, u) | u)
        |
          t, ", " order by i
        ) + any(string more | if n > 3 then more = " +" + (n - 3) else more = "")
  )
}

from Location l, string entry, string name, string location, string from_, string members
where
  // one result even if CodeQL keeps several functions there
  l = any(Function f | row(entry, name, location, f, _)).getLocation() and
  (
    if origins(entry, name, location) = ""
    then from_ = ""
    else from_ = " from " + origins(entry, name, location)
  ) and
  (
    if members(entry, name, location) = ""
    then members = ""
    else members = ", narrowed to " + members(entry, name, location)
  )
select l,
  entry + ": " + name + " hands out memory" + from_ + members + "; it is used as " +
    usedAsList(entry, name, location) + "."
