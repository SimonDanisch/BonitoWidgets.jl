using BonitoWidgets, Bonito
using Documenter

ci = get(ENV, "CI", "false") == "true"

makedocs(
    modules = [BonitoWidgets],
    sitename = "BonitoWidgets",
    clean = false,
    authors = "Simon Danisch and contributors",
    # Bonito apps export as a single self-contained HTML blob (all assets
    # inlined), so individual pages can be large — don't cap the size.
    format = Documenter.HTML(prettyurls = ci, size_threshold = nothing),
    pages = [
        "Home" => "index.md",
        "Workspace" => "workspace.md",
        "Components" => "components.md",
        "Theming" => "theming.md",
        "Testing layouts" => "testing.md",
        "API" => "api.md",
    ],
)

if ci
    deploydocs(repo = "github.com/SimonDanisch/BonitoWidgets.jl.git"; push_preview = true)
end
