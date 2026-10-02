-- truth-table core: pure logic with no Neovim dependency.
--
-- Everything here is a plain function over strings and tables: no `vim.*`, no
-- buffers, no side effects. That boundary keeps the parser, evaluator, and
-- formatter unit-testable under a bare Lua interpreter (busted). The one place
-- that wants Neovim (display-width measurement) is injectable: M.display_width
-- has a pure default, and the vim layer swaps in vim.fn.strdisplaywidth.

local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Pure default: count UTF-8 codepoints (each as one column) by counting bytes
-- that are not continuation bytes. The Neovim layer overrides this with
-- vim.fn.strdisplaywidth for terminal-accurate widths (e.g. East Asian wide
-- characters); for the ASCII names and width-1 logic symbols this tool emits,
-- the two agree.
function M.display_width(str)
    local _, count = str:gsub("[^\128-\191]", "")
    return count
end

function M.center_pad(str, width)
    local pad = width - M.display_width(str)
    local left = math.floor(pad / 2)
    local right = pad - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

function M.format_table(headers, rows)
    local widths = {}
    for i, h in ipairs(headers) do
        widths[i] = math.max(3, M.display_width(h))
    end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            widths[i] = math.max(widths[i], M.display_width(cell))
        end
    end

    local hdr_cells = {}
    for i, h in ipairs(headers) do
        hdr_cells[i] = " " .. M.center_pad(h, widths[i]) .. " "
    end
    local heading = "|" .. table.concat(hdr_cells, "|") .. "|"

    local sep_cells = {}
    for i = 1, #headers do
        sep_cells[i] = ":" .. string.rep("-", widths[i]) .. ":"
    end
    local separator = "|" .. table.concat(sep_cells, "|") .. "|"

    local lines = { heading, separator }
    for _, row in ipairs(rows) do
        local cells = {}
        for i, cell in ipairs(row) do
            cells[i] = " " .. M.center_pad(cell, widths[i]) .. " "
        end
        lines[#lines + 1] = "|" .. table.concat(cells, "|") .. "|"
    end

    return lines
end

-- All 2^n rows of bits for n variables, MSB-first (col 1 is the high bit).
function M.generate_rows(n)
    local total = 2 ^ n
    local rows = {}
    for i = 0, total - 1 do
        local row = {}
        for col = 1, n do
            local bit = math.floor(i / (2 ^ (n - col))) % 2
            row[col] = tostring(bit)
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- Parse the :TruthTable argument: either an integer N (-> headers A, B, C, ...)
-- or a list of variable names. Returns headers, or nil + an error message.
function M.parse_truth_table_args(args)
    local input = trim(args)
    if input == "" then
        return nil, "Usage: :TruthTable N or :TruthTable name1 name2 ..."
    end

    local n = tonumber(input)
    if n then
        if n < 1 or n > 10 or n ~= math.floor(n) then
            return nil, "N must be an integer between 1 and 10"
        end
        local headers = {}
        for i = 1, n do
            headers[i] = string.char(64 + i)
        end
        return headers
    end

    local headers = {}
    local seen = {}
    for name in input:gmatch("%S+") do
        if not name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            return nil, "Invalid variable name: " .. name
        end
        if seen[name] then
            return nil, "Duplicate variable name: " .. name
        end
        seen[name] = true
        headers[#headers + 1] = name
    end

    if #headers > 10 then
        return nil, "Too many variables (max 10)"
    end

    return headers
end

function M.is_table_line(line)
    return line:match("^%s*|.*|%s*$") ~= nil
end

function M.is_separator(line)
    local inner = line:match("^%s*|(.+)|%s*$")
    if not inner then
        return false
    end
    for cell in (inner .. "|"):gmatch("(.-)%|") do
        if not cell:match("^%s*:?%-+:?%s*$") then
            return false
        end
    end
    return true
end

function M.split_row(line)
    local cells = {}
    local inner = line:match("^%s*|(.+)|%s*$")
    if not inner then
        return cells
    end
    for cell in (inner .. "|"):gmatch("(.-)%|") do
        cells[#cells + 1] = trim(cell)
    end
    return cells
end

-- Parse a markdown table (heading, separator, data rows) into its parts.
function M.parse_table_lines(lines)
    local headers = M.split_row(lines[1])
    local rows = {}
    for i = 3, #lines do
        rows[#rows + 1] = M.split_row(lines[i])
    end
    return { headers = headers, rows = rows }
end

-- ---------------------------------------------------------------------------
-- Predicate language: tokenizer -> recursive-descent parser -> AST.
-- Precedence (loosest to tightest): iff, implies, xor, or, and, unary not, atom.
-- ---------------------------------------------------------------------------

local KEYWORDS = { ["and"] = true, ["or"] = true, ["xor"] = true, ["not"] = true, ["implies"] = true, ["iff"] = true }
local BINARY = { ["and"] = true, ["or"] = true, ["xor"] = true, ["implies"] = true, ["iff"] = true }

-- Symbol spellings of the operators, so a rendered heading (or anything pasted
-- from one) parses back to the AST it was rendered from. Multi-character (or
-- multibyte), hence matched as whole strings and not through the single-byte
-- `ch` dispatch. First match wins, so `=>` and `<=>` must precede `=`.
local SYMBOL_OPS = {
    { "∧", "and" },
    { "∨", "or" },
    { "⊕", "xor" },
    { "¬", "not" },
    { "→", "implies" },
    { "⇒", "implies" },
    { "=>", "implies" },
    { "⇔", "iff" },
    { "↔", "iff" },
    { "<->", "iff" },
    { "<=>", "iff" },
    { "=", "iff" },
}

local function symbol_op_at(input, pos)
    for _, entry in ipairs(SYMBOL_OPS) do
        local symbol = entry[1]
        if input:sub(pos, pos + #symbol - 1) == symbol then
            return entry[2], #symbol
        end
    end
end

function M.tokenize(input)
    local tokens = {}
    local pos = 1
    local len = #input

    while pos <= len do
        local ws = input:match("^%s+", pos)
        if ws then
            pos = pos + #ws
        end
        if pos > len then
            break
        end

        local ch = input:sub(pos, pos)
        local symbol_op, symbol_len = symbol_op_at(input, pos)

        if symbol_op then
            tokens[#tokens + 1] = { type = "op", value = symbol_op }
            pos = pos + symbol_len
        elseif ch == "(" or ch == ")" then
            tokens[#tokens + 1] = { type = "paren", value = ch }
            pos = pos + 1
        elseif ch == "!" then
            tokens[#tokens + 1] = { type = "op", value = "!" }
            pos = pos + 1
        elseif ch:match("[A-Za-z_]") then
            local ident = input:match("^[A-Za-z_][A-Za-z0-9_]*", pos)
            if KEYWORDS[ident] then
                tokens[#tokens + 1] = { type = "op", value = ident }
            else
                tokens[#tokens + 1] = { type = "ident", value = ident }
            end
            pos = pos + #ident
        elseif ch == "-" and input:sub(pos, pos + 1) == "->" then
            tokens[#tokens + 1] = { type = "op", value = "implies" }
            pos = pos + 2
        elseif ch == "0" or ch == "1" then
            tokens[#tokens + 1] = { type = "literal", value = ch }
            pos = pos + 1
        else
            return nil, "Unexpected character: " .. ch .. " at position " .. pos
        end
    end

    return tokens
end

function M.parse_predicate(tokens)
    local pos = 1

    local function peek()
        return tokens[pos]
    end

    local function consume()
        local tok = tokens[pos]
        pos = pos + 1
        return tok
    end

    local function expect(type, value)
        local tok = peek()
        if not tok or tok.type ~= type or (value and tok.value ~= value) then
            return nil, "Expected " .. (value or type) .. " at token " .. pos
        end
        return consume()
    end

    local parse_expr

    local function parse_atom()
        local tok = peek()
        if not tok then
            return nil, "Unexpected end of expression"
        end

        if tok.type == "ident" then
            consume()
            return { type = "var", name = tok.value }
        elseif tok.type == "literal" then
            consume()
            return { type = "literal", value = tonumber(tok.value) }
        elseif tok.type == "paren" and tok.value == "(" then
            consume()
            local node, err = parse_expr()
            if not node then
                return nil, err
            end
            local ok, err2 = expect("paren", ")")
            if not ok then
                return nil, err2 or "Expected closing parenthesis"
            end
            return { type = "paren", expr = node }
        else
            return nil, "Unexpected token: " .. tok.value
        end
    end

    local function parse_unary()
        local tok = peek()
        if tok and tok.type == "op" and (tok.value == "not" or tok.value == "!") then
            consume()
            local operand, err = parse_unary()
            if not operand then
                return nil, err
            end
            return { type = "not", operand = operand }
        end
        return parse_atom()
    end

    local function parse_and()
        local left, err = parse_unary()
        if not left then
            return nil, err
        end
        while peek() and peek().type == "op" and peek().value == "and" do
            consume()
            local right, err2 = parse_unary()
            if not right then
                return nil, err2
            end
            left = { type = "and", left = left, right = right }
        end
        return left
    end

    local function parse_or()
        local left, err = parse_and()
        if not left then
            return nil, err
        end
        while peek() and peek().type == "op" and peek().value == "or" do
            consume()
            local right, err2 = parse_and()
            if not right then
                return nil, err2
            end
            left = { type = "or", left = left, right = right }
        end
        return left
    end

    local function parse_xor()
        local left, err = parse_or()
        if not left then
            return nil, err
        end
        while peek() and peek().type == "op" and peek().value == "xor" do
            consume()
            local right, err2 = parse_or()
            if not right then
                return nil, err2
            end
            left = { type = "xor", left = left, right = right }
        end
        return left
    end

    local function parse_implies()
        local left, err = parse_xor()
        if not left then
            return nil, err
        end
        while peek() and peek().type == "op" and peek().value == "implies" do
            consume()
            local right, err2 = parse_xor()
            if not right then
                return nil, err2
            end
            left = { type = "implies", left = left, right = right }
        end
        return left
    end

    local function parse_iff()
        local left, err = parse_implies()
        if not left then
            return nil, err
        end
        while peek() and peek().type == "op" and peek().value == "iff" do
            consume()
            local right, err2 = parse_implies()
            if not right then
                return nil, err2
            end
            left = { type = "iff", left = left, right = right }
        end
        return left
    end

    parse_expr = parse_iff

    local result, err = parse_expr()
    if not result then
        return nil, err
    end

    if pos <= #tokens then
        return nil, "Unexpected token after expression: " .. tokens[pos].value
    end

    return result
end

function M.validate_vars(node, header_set)
    if node.type == "paren" then
        return M.validate_vars(node.expr, header_set)
    elseif node.type == "var" then
        if not header_set[node.name] then
            return "Unknown column: " .. node.name
        end
    elseif node.type == "not" then
        return M.validate_vars(node.operand, header_set)
    elseif BINARY[node.type] then
        local err = M.validate_vars(node.left, header_set)
        if err then
            return err
        end
        return M.validate_vars(node.right, header_set)
    end
    return nil
end

M.SYMBOLS = {
    ["and"] = "∧",
    ["or"] = "∨",
    ["xor"] = "⊕",
    ["not"] = "¬",
    ["!"] = "¬",
    ["implies"] = "→",
    ["iff"] = "=",
}

function M.eval_ast(node, ctx)
    if node.type == "paren" then
        return M.eval_ast(node.expr, ctx)
    elseif node.type == "var" then
        return ctx[node.name]
    elseif node.type == "literal" then
        return node.value
    elseif node.type == "not" then
        return M.eval_ast(node.operand, ctx) == 0 and 1 or 0
    elseif node.type == "and" then
        return (M.eval_ast(node.left, ctx) == 1 and M.eval_ast(node.right, ctx) == 1) and 1 or 0
    elseif node.type == "or" then
        return (M.eval_ast(node.left, ctx) == 1 or M.eval_ast(node.right, ctx) == 1) and 1 or 0
    elseif node.type == "xor" then
        return M.eval_ast(node.left, ctx) ~= M.eval_ast(node.right, ctx) and 1 or 0
    elseif node.type == "implies" then
        return (M.eval_ast(node.left, ctx) == 0 or M.eval_ast(node.right, ctx) == 1) and 1 or 0
    elseif node.type == "iff" then
        return M.eval_ast(node.left, ctx) == M.eval_ast(node.right, ctx) and 1 or 0
    end
end

function M.ast_to_heading(node)
    if node.type == "paren" then
        return "(" .. M.ast_to_heading(node.expr) .. ")"
    elseif node.type == "var" then
        return node.name
    elseif node.type == "literal" then
        return tostring(node.value)
    elseif node.type == "not" then
        return M.SYMBOLS["not"] .. M.ast_to_heading(node.operand)
    elseif BINARY[node.type] then
        return M.ast_to_heading(node.left) .. " " .. M.SYMBOLS[node.type] .. " " .. M.ast_to_heading(node.right)
    end
end

-- Compute new headers + rows for `tbl` extended with one column per predicate
-- string. Pure: parsing, validation, and evaluation only. Returns
-- new_headers, new_rows on success, or nil + an error message on failure.
function M.expand(tbl, predicate_strings)
    local header_set = {}
    for _, h in ipairs(tbl.headers) do
        header_set[h] = true
    end

    local parsed = {}
    for _, pred_str in ipairs(predicate_strings) do
        pred_str = trim(pred_str)
        local tokens, tok_err = M.tokenize(pred_str)
        if not tokens then
            return nil, "Parse error: " .. tok_err
        end
        local ast, parse_err = M.parse_predicate(tokens)
        if not ast then
            return nil, 'Parse error in "' .. pred_str .. '": ' .. parse_err
        end
        local var_err = M.validate_vars(ast, header_set)
        if var_err then
            return nil, var_err
        end
        parsed[#parsed + 1] = { ast = ast, heading = M.ast_to_heading(ast) }
    end

    local new_headers = {}
    for _, h in ipairs(tbl.headers) do
        new_headers[#new_headers + 1] = h
    end
    for _, p in ipairs(parsed) do
        new_headers[#new_headers + 1] = p.heading
    end

    local new_rows = {}
    for _, row in ipairs(tbl.rows) do
        local ctx = {}
        for i, h in ipairs(tbl.headers) do
            ctx[h] = tonumber(row[i])
        end
        local new_row = {}
        for _, cell in ipairs(row) do
            new_row[#new_row + 1] = cell
        end
        for _, p in ipairs(parsed) do
            new_row[#new_row + 1] = tostring(M.eval_ast(p.ast, ctx))
        end
        new_rows[#new_rows + 1] = new_row
    end

    return new_headers, new_rows
end

-- Append to `vars` each variable name in the AST that `seen` has not recorded
-- yet, in order of first appearance (left to right).
local function collect_vars(node, seen, vars)
    if node.type == "var" then
        if not seen[node.name] then
            seen[node.name] = true
            vars[#vars + 1] = node.name
        end
    elseif node.type == "paren" then
        collect_vars(node.expr, seen, vars)
    elseif node.type == "not" then
        collect_vars(node.operand, seen, vars)
    elseif BINARY[node.type] then
        collect_vars(node.left, seen, vars)
        collect_vars(node.right, seen, vars)
    end
end

-- Does the :TruthTable argument use the expression form? The classic forms (an
-- integer, or a list of names) consist of word characters and spaces only, so
-- any other character, or an operator keyword among the names, means
-- expressions. N.B. this reserves the operator keywords: `:TruthTable p or q`
-- is the expression p ∨ q, where it used to be three variables.
function M.is_expression_input(args)
    if args:match("[^%w_%s]") then
        return true
    end
    for word in args:gmatch("%S+") do
        if KEYWORDS[word] then
            return true
        end
    end
    return false
end

-- Build a whole table from expressions separated by `|` or `,`. The variables
-- are whatever names the expressions mention, in order of first appearance;
-- each compound expression becomes a computed column. A bare variable adds no
-- column of its own, which makes it a way to pin the variable order
-- (`b | a | a -> b`). Returns headers, rows, or nil + an error message.
local function table_from_expressions(input)
    local vars, seen = {}, {}
    local compound, seen_heading = {}, {}

    for pred_str in input:gmatch("[^|,]+") do
        pred_str = trim(pred_str)
        if pred_str ~= "" then
            local tokens, tok_err = M.tokenize(pred_str)
            if not tokens then
                return nil, "Parse error: " .. tok_err
            end
            local ast, parse_err = M.parse_predicate(tokens)
            if not ast then
                return nil, 'Parse error in "' .. pred_str .. '": ' .. parse_err
            end
            collect_vars(ast, seen, vars)

            local heading = M.ast_to_heading(ast)
            if ast.type ~= "var" and not seen_heading[heading] then
                seen_heading[heading] = true
                compound[#compound + 1] = pred_str
            end
        end
    end

    if #vars == 0 then
        return nil, "No variables in: " .. trim(input)
    end
    if #vars > 10 then
        return nil, "Too many variables (max 10)"
    end

    return M.expand({ headers = vars, rows = M.generate_rows(#vars) }, compound)
end

-- The :TruthTable argument spelled out over several lines (a visual selection):
-- a line break is one more column delimiter. Blank lines are skipped.
function M.args_from_lines(lines)
    local parts = {}
    for _, line in ipairs(lines) do
        line = trim(line)
        if line ~= "" then
            parts[#parts + 1] = line
        end
    end
    return table.concat(parts, " | ")
end

-- Headers + rows for any :TruthTable argument: an integer N, a list of names,
-- or expressions (see M.is_expression_input). Returns nil + an error message
-- on failure.
function M.build_truth_table(args)
    if M.is_expression_input(args) then
        return table_from_expressions(args)
    end

    local headers, err = M.parse_truth_table_args(args)
    if not headers then
        return nil, err
    end
    return headers, M.generate_rows(#headers)
end

-- Toggle every cell between 0/1 and F/T, in place. The direction is decided by
-- the first data cell: T/F -> 0/1, otherwise 0/1 -> T/F. Returns the rows.
function M.toggle_cells(rows)
    local uses_tf = false
    if #rows > 0 and #rows[1] > 0 then
        local first = rows[1][1]
        uses_tf = (first == "T" or first == "F")
    end

    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            if uses_tf then
                if cell == "T" then
                    row[i] = "1"
                elseif cell == "F" then
                    row[i] = "0"
                end
            else
                if cell == "1" then
                    row[i] = "T"
                elseif cell == "0" then
                    row[i] = "F"
                end
            end
        end
    end

    return rows
end

return M
