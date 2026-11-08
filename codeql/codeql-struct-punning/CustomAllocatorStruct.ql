/**
 * @name Custom allocator result used as a struct
 * @description A call to a project-specific allocator (see Allocators.qll)
 *              whose result is converted to a pointer to a struct. FSan sees
 *              the allocation only if the allocator is a known allocation
 *              function.
 * @kind problem
 * @problem.severity recommendation
 * @id fsan/custom-allocator-struct
 */

import cpp
import Allocators
import Locations

module AllocConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node n) { customAllocator(n.asExpr().(Call).getTarget(), _) }

  predicate isSink(DataFlow::Node n) {
    exists(Cast c | n.asExpr() = c.getExpr() and pointsToStruct(c.getType(), _))
  }
}

module Alloc = DataFlow::Global<AllocConfig>;

from DataFlow::Node source, DataFlow::Node sink, Call call, Function f, Cast c, Class s
where
  Alloc::flow(source, sink) and
  call = source.asExpr() and
  f = call.getTarget() and
  sink.asExpr() = c.getExpr() and
  pointsToStruct(c.getType(), s) and
  // report `xzalloc(...)` at the caller, not the `xmalloc` call inside xzalloc,
  // unless the allocator itself converts (`struct S *new_s(void) { return xmalloc(...); }`)
  (
    not customAllocator(call.getEnclosingFunction(), _) or
    c.getEnclosingFunction() = call.getEnclosingFunction()
  )
select call,
  "Custom allocator $@ (" + allocatorReasons(f) + ") returns a struct $@ at $@.", f,
  withLoc(f.getName(), f), s, withLoc(s.getName(), s), c, withLoc("this conversion", c)
