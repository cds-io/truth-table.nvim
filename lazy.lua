-- The plugin's own lazy.nvim spec, read from this file by lazy's pkg source
-- and merged into whatever spec the reader wrote. Eager, since the insert-mode
-- abbreviations are global and want to be there at startup. The house library
-- is a dependency pinned to a commit, loaded on its first require, so
-- `require("cds.fp")` resolves to one copy on the runtimepath however many
-- plugins of the family are installed.
return {
    "cds-io/truth-table.nvim",
    lazy = false,
    dependencies = {
        { "cds-io/cds-lua", commit = "13a84f07c1e08f070c2db74e78486852afba2a9a", lazy = true },
    },
}
