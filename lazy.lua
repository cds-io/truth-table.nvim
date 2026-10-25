-- The plugin's own lazy.nvim spec, read from this file by lazy's pkg source
-- and merged into whatever spec the reader wrote. Eager, since the insert-mode
-- abbreviations are global and want to be there at startup. The vocabulary rock,
-- cds-lua-fp, is the one dependency, tracking its main and loaded on its first
-- require, so `require("cds.fp")` resolves to one copy on the runtimepath
-- however many plugins of the family are installed.
return {
    "cds-io/truth-table.nvim",
    lazy = false,
    dependencies = {
        { "cds-io/cds-lua-fp", lazy = true },
    },
}
