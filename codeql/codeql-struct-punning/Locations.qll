/**
 * `file:line` for the elements a message names, so that every place a result
 * refers to can be looked up, not only the result's own location. Paths are
 * relative to the source root, like result locations in SARIF; files outside
 * it keep their absolute path.
 */

import cpp

private string path(File f) {
  if exists(f.getRelativePath()) then result = f.getRelativePath() else result = f.getAbsolutePath()
}

/** `e`'s location as `file:line`. A type defined in several files gets one of them. */
string loc(Element e) {
  result =
    min(string s |
      exists(Location l | l = e.getLocation() and l.getStartLine() > 0 |
        s = path(l.getFile()) + ":" + l.getStartLine()
      )
    )
}

/** `name (file:line)`, or `name` alone if `e` has no location. */
bindingset[name]
string withLoc(string name, Element e) {
  if exists(loc(e)) then result = name + " (" + loc(e) + ")" else result = name
}
