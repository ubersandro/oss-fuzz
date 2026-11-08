/**
 * @name Struct pointer reinterpreted as an unrelated struct type
 * @description A pointer to one struct type flows into a cast to a pointer to a
 *              different, unrelated struct type. FSan reports field accesses
 *              through such pointers as tag mismatches (type punning, not a
 *              bounds violation); the struct types are blocklist candidates.
 * @kind problem
 * @problem.severity warning
 * @id fsan/struct-punning
 */

import cpp
import Punning
import Locations

from Cast c, Struct fromT, Struct toT, Expr o, int others, string more
where
  punning(c, fromT, toT) and
  // the message names one origin and counts the others
  o =
    min(Expr e |
      e = origin(c, fromT)
    |
      e
      order by
        e.getLocation().getFile().getAbsolutePath(), e.getLocation().getStartLine(),
        e.getLocation().getStartColumn()
    ) and
  others = count(origin(c, fromT)) - 1 and
  (
    others = 0 and more = ""
    or
    others = 1 and more = " and 1 other place"
    or
    others > 1 and more = " and " + others + " other places"
  )
select c,
  "Pointer to $@ reinterpreted as $@. The " + typeName(fromT) + " pointer comes from $@" + more +
    ".", fromT, withLoc(typeName(fromT), fromT), toT, withLoc(typeName(toT), toT), o,
  withLoc(o.toString(), o)
