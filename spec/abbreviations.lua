-- Insert-mode abbreviations: defaults from the plugin entry point, then every
-- shape of the setup({ abbreviations = ... }) option. Each setup call must
-- leave exactly its own set registered, whatever the call before it did.
vim.opt.rtp:append(vim.fn.getcwd())
package.preload['which-key'] = function() error('which-key intentionally absent') end
vim.cmd('runtime plugin/truth-table.lua')

local function abbrev(lhs)
    return vim.fn.maparg(lhs, 'i', true)
end
local tt = require('truth-table')
local symbols = require('truth-table.symbols')
local defaults = require('truth-table.abbreviations').defaults

-- The defaults pair each constant's ascii word plus `@` with its unicode symbol.
assert(defaults.trigger == '@')
for _, key in ipairs({ 'NOT', 'AND', 'OR', 'XOR', 'IMPLIES', 'IFF', 'FORALL', 'EXISTS', 'TOP', 'BOTTOM', 'EQUIV' }) do
    assert(defaults.symbols[symbols[key].ascii] == symbols[key].unicode, key)
end

-- Bare setup from plugin/ registers every default, including the shared
-- rendering for implies and iff.
for word, symbol in pairs(defaults.symbols) do
    assert(abbrev(word .. '@') == symbol, word)
end
assert(abbrev('iff@') == '⇔')
assert(abbrev('implies@') == '→')
assert(abbrev('equiv@') == '≡')

-- false registers none, and undoes the earlier call.
tt.setup({ abbreviations = false })
for word in pairs(defaults.symbols) do
    assert(abbrev(word .. '@') == '', word)
end

-- A later bare setup brings the defaults back.
tt.setup()
assert(abbrev('and@') == '∧')

-- symbols merges over the defaults: override one, drop one, add one.
tt.setup({ abbreviations = { symbols = { implies = '⇒', forall = false, top = '⊤' } } })
assert(abbrev('implies@') == '⇒')
assert(abbrev('forall@') == '')
assert(abbrev('top@') == '⊤')
assert(abbrev('and@') == '∧')

-- trigger changes the input side for every word, and the old lhs is gone.
tt.setup({ abbreviations = { trigger = ';' } })
assert(abbrev('and;') == '∧')
assert(abbrev('and@') == '')
assert(abbrev('top;') == '')

-- Reverting to defaults drops the added entry, and survives an abbreviation
-- the user already removed by hand.
tt.setup({ abbreviations = { symbols = { top = '⊤' } } })
vim.cmd('iunabbrev and@')
tt.setup()
assert(abbrev('and@') == '∧')
assert(abbrev('top@') == '')
assert(abbrev('implies@') == '→')

print('Abbreviation setup passed')

-- Existing user mappings are restored with their original options.
tt.setup({ abbreviations = false })
vim.cmd('inoreabbrev <silent> and@ ORIGINAL')
local original = vim.fn.maparg('and@', 'i', true, true)
tt.setup()
assert(abbrev('and@') == '∧')
tt.setup({ abbreviations = false })
local restored = vim.fn.maparg('and@', 'i', true, true)
assert(restored.rhs == 'ORIGINAL' and restored.noremap == original.noremap and restored.silent == original.silent)
vim.cmd('iunabbrev and@')

-- User replacements made after setup are not removed by disabling the plugin.
tt.setup()
vim.cmd('iabbrev and@ USER_REPLACEMENT')
tt.setup({ abbreviations = false })
assert(abbrev('and@') == 'USER_REPLACEMENT')
vim.cmd('iunabbrev and@')

-- Global ownership works even under a buffer-local shadow.
vim.cmd('iabbrev and@ GLOBAL')
vim.cmd('iabbrev <buffer> and@ LOCAL')
tt.setup()
assert(abbrev('and@') == 'LOCAL')
tt.setup({ abbreviations = false })
assert(abbrev('and@') == 'LOCAL')
vim.cmd('iunabbrev <buffer> and@')
assert(abbrev('and@') == 'GLOBAL')
vim.cmd('iunabbrev and@')

-- Invalid settings fail before deleting or registering any abbreviations.
tt.setup()
local before = vim.fn.maplist(true)
for _, option in ipairs({
    true, { trigger = ' x' }, { trigger = '' }, { trigger = 'xx' }, { trigger = '|' },
    { symbols = true }, { symbols = { ['bad key'] = 'X' } },
    { symbols = { and_word = 1 } }, { symbols = { and_word = '' } },
    { symbols = { and_word = 'X\nY' } },
}) do
    local ok, err = pcall(tt.setup, { abbreviations = option })
    assert(not ok and err:find('Invalid truth-table configuration', 1, true))
    assert(vim.deep_equal(before, vim.fn.maplist(true)))
end
assert(abbrev('and') == '' and abbrev('bad') == '')

-- A literal pipe on the RHS stays text, not an Ex command separator.
tt.setup({ abbreviations = { symbols = { and_word = 'A|B' } } })
assert(abbrev('and_word@') == 'A|B')
tt.setup()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
vim.api.nvim_win_set_cursor(0, {1, 0})
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('iand@<C-]> <Esc>', true, false, true), 'xt', false)
assert(vim.api.nvim_get_current_line() == '∧ ', vim.inspect(vim.api.nvim_get_current_line()))
print('Abbreviation ownership, validation, and expansion passed')
