using BonitoWidgets, Bonito
using Documenter

ci = get(ENV, "CI", "false") == "true"

home = (
    name = "BonitoWidgets",
    text = "Layout components for Bonito",
    tagline = "Tabs, resizable splits, VSCode-style workspaces, collapsibles and " *
              "floating windows. Mouse and touch, light and dark.",
    actions = [
        (text = "Get Started", link = "workspace.html", theme = "brand"),
        (text = "View on GitHub", link = "https://github.com/SimonDanisch/BonitoWidgets.jl", theme = "alt"),
    ],
    features = [
        (title = "Workspace",
         details = "A split tree of tab groups. Drag a tab to split or merge; panels move without re-rendering.",
         link = "workspace.html"),
        (title = "Components",
         details = "Tabs, splits, collapsibles and floating windows as standalone building blocks.",
         link = "components.html"),
        (title = "Theming",
         details = "Style everything through `--bw-*` CSS variables, with light and dark defaults.",
         link = "theming.html"),
        (title = "Testing layouts",
         details = "Drive the widgets from code in a real Electron window.",
         link = "testing.html"),
    ],
)

makedocs(
    modules = [BonitoWidgets],
    sitename = "BonitoWidgets",
    authors = "Simon Danisch and contributors",
    format = Bonito.DocumenterBonito(
        repo = "github.com/SimonDanisch/BonitoWidgets.jl",
        devbranch = "main",
        devurl = "dev",
        version = "dev",
        home = home,
    ),
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
