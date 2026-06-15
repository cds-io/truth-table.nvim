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
-- Precedence (loosest to tightest): implies, xor, or, and, unary not, atom.
-- ---------------------------------------------------------------------------

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

        if ch == "(" or ch == ")" then
            tokens[#tokens + 1] = { type = "paren", value = ch }
            pos = pos + 1
        elseif ch == "!" then
            tokens[#tokens + 1] = { type = "op", value = "!" }
            pos = pos + 1
        elseif ch:match("[A-Za-z_]") then
            local ident = input:match("^[A-Za-z_][A-Za-z0-9_]*", pos)
            if ident == "and" or ident == "or" or ident == "xor" or ident == "not" or ident == "implies" then
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

    parse_expr = parse_implies

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
    elseif node.type == "and" or node.type == "or" or node.type == "xor" or node.type == "implies" then
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
    elseif node.type == "and" or node.type == "or" or node.type == "xor" or node.type == "implies" then
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
