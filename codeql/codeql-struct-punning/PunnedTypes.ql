/**
 * @name Struct types punned into each other
 * @description One result per pair of struct types where a pointer to the first
 *              is reinterpreted as a pointer to the second, with the message
 *              `"struct A" : "struct B"`. The result is at the first such cast;
 *              StructPunning.ql reports every cast.
 * @kind problem
 * @problem.severity warning
 * @id fsan/punned-types
 */

import cpp
import Punning

from Struct fromT, Struct toT, Cast c
where
  exists(Cast k | punning(k, fromT, toT)) and
  c =
    min(Cast k |
      punning(k, fromT, toT)
    |
      k
      order by
        k.getLocation().getFile().getAbsolutePath(), k.getLocation().getStartLine(),
        k.getLocation().getStartColumn()
    )
select c, "\"" + typeName(fromT) + "\" : \"" + typeName(toT) + "\""
