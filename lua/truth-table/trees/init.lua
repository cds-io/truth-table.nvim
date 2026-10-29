-- Syntax trees of the predicate language: taking one apart and putting one
-- together, copying one through a transformation, its canonical form and its
-- text. Pure: trees in, trees out, and no input tree is changed. The parser
-- that makes them is truth-table.predicate; this module never reads source.
--
-- A tree is a table with a `type`: "var" (name), "reference" (index, from
-- :hN), "column" (index, with name or variable; what binding makes of the
-- two before it), "literal" (value, and the symbol it was typed as), "paren"
-- (expr), "not" (operand), or a binary operator's name (left, right). A node
-- has no editor annotations. Provenance is supplied separately to rendered().
--
-- Every node is made by a constructor in node.lua; the parser and the rewrites
-- call them, and no other code spells a node. So the types a traversal
-- meets are the ones listed, `binary` is where a wrong operator name is
-- refused, and a tree transform() does not know is a programming error,
-- which rendered() raises on.
--
-- Three modules carry this, and this composes them under one name: node.lua
-- makes and walks the nodes, render.lua gives the canonical form and the
-- text, laws.lua the whole-tree rewrites (unfold, De Morgan).
local node = require("truth-table.trees.node")
local render = require("truth-table.trees.render")
local laws = require("truth-table.trees.laws")
local M = {}

for _, part in ipairs({ node, render, laws }) do
    for name, fn in pairs(part) do
        M[name] = fn
    end
end

return M
