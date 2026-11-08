/**
 * @name Arena or recycler allocator and its arena object
 * @description A custom allocator that carves memory out of an arena or
 *              recycler object (or wraps one that does), with the struct type
 *              of that object and where the object is instantiated: by an
 *              allocation call, or as a static instance. FSan sees one object
 *              (the arena's buffer), not the objects handed out.
 * @kind problem
 * @problem.severity recommendation
 * @id fsan/arena-allocator
 */

import cpp
import Allocators
import Locations

/**
 * `f` carves memory from field `fld` of the `arena` object `obj`, itself or
 * through allocators it wraps.
 */
predicate arenaOf(Function f, Struct arena, Field fld, Variable obj) {
  carves(f, arena, fld, obj)
  or
  exists(Call c | returnsCall(f, c) and arenaOf(c.getTarget(), arena, fld, obj))
}

predicate isStatic(Variable v) {
  v instanceof GlobalOrNamespaceVariable or v.(LocalVariable).isStatic() or v instanceof MemberVariable and v.isStatic()
}

/** `site` instantiates an object of struct `t`; `how` names the allocator. */
predicate instantiates(Element site, Struct t, string how) {
  exists(Call a, Cast c |
    (a instanceof AllocationExpr or customAllocator(a.getTarget(), _)) and
    DataFlow::localExprFlow(a, c.getExpr()) and
    pointsToStruct(c.getType(), t) and
    site = a and
    how = "allocated by " + a.getTarget().getName() + "()"
  )
  or
  exists(NewExpr n | n.getAllocatedType().getUnspecifiedType() = t and site = n and how = "allocated by new")
  or
  exists(Variable v |
    v.getUnspecifiedType() = t and
    isStatic(v) and
    site = v and
    how = "static instance " + v.getName()
  )
}

from Function f, Struct arena, Field fld, Variable obj, Element site, string how, string siteText
where
  arenaOf(f, arena, fld, obj) and
  (
    // a static arena (`R.free`) is that object; a parameter or pointer
    // (`r->free`) may be any instance of the type
    isStatic(obj) and obj.getUnspecifiedType() = arena and site = obj and how = "static instance " + obj.getName()
    or
    not (isStatic(obj) and obj.getUnspecifiedType() = arena) and
    (
      instantiates(site, arena, how)
      or
      not instantiates(_, arena, _) and site = fld and how = "no instantiation found"
    )
  ) and
  // the field already has its location in the message
  (if site = fld then siteText = how else siteText = withLoc(how, site))
select f,
  "Custom allocator " + f.getName() + " (" + allocatorReasons(f) +
    ") hands out memory from $@; arena object: $@.", fld,
  withLoc(arena.getName() + "." + fld.getName(), fld), site, siteText
