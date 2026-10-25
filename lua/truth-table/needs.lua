-- What the plugin needs from cds-lua-fp, by module and function. lazy.lua names
-- the dependency; this names what has to be there
-- for it to run, whichever commit is installed, since one cds-lua-fp serves
-- every plugin of the family and cds-lua-fp grows by addition. cds.needs checks
-- it at startup, and the spec harness holds the plugin to the same list.
---@type table<string, string[]>
return {
    fp = { "all", "any", "filter", "find", "map", "reduce", "set", "unique" },
    result = { "bind", "context", "map", "traverse" },
}
