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

from Call call, Function f, Cast c, Class s
where
  allocatorResult(call, c, s) and
  f = call.getTarget()
select call, "Custom allocator $@ (" + allocatorReasons(f) + ") returns a struct $@ at $@.", f,
  withLoc(f.getName(), f), s, withLoc(s.getName(), s), c, withLoc("this conversion", c)
