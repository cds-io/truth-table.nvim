-- One record per logic symbol: the ASCII word the predicate language accepts
-- and the Unicode character it renders. Pure Lua 5.1, no vim dependency.
--
-- Everything that spells a symbol reads it from here: predicate.lua renders
-- headings with `unicode`, and abbreviations.lua turns `ascii .. trigger` into
-- `unicode`. Changing a rendering means changing one line, and typed headings
-- always match generated ones. The last five are not predicate operators;
-- they are here for the abbreviations and for anything that later wants them.

return {
    NOT = { ascii = "not", unicode = "¬" },
    AND = { ascii = "and", unicode = "∧" },
    OR = { ascii = "or", unicode = "∨" },
    XOR = { ascii = "xor", unicode = "⊕" },
    IMPLIES = { ascii = "implies", unicode = "→" },
    IFF = { ascii = "iff", unicode = "⇔" },
    FORALL = { ascii = "forall", unicode = "∀" },
    EXISTS = { ascii = "exists", unicode = "∃" },
    TOP = { ascii = "true", unicode = "⊤" },
    BOTTOM = { ascii = "false", unicode = "⊥" },
    EQUIV = { ascii = "equiv", unicode = "≡" },
}
