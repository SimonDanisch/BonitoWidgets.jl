# BonitoWidgets

Reusable, stylable layout components for [Bonito.jl](https://github.com/SimonDanisch/Bonito.jl):
tabs, resizable splits, VSCode-style panel groups, collapsibles, and floating
windows — optimized for both desktop and mobile.

Distilled from the layout code in ReynKoWebViz, BonitoBook, and BonitoTeam.

The widgets below are **live** — they are real Bonito apps exported into this
page, so go ahead and click tabs, drag gutters, and tear panels off. Here they
are driven end-to-end in a real Electron window (see [Testing layouts](@ref)):

```@raw html
<video src="assets/walkthrough.mp4" controls loop muted width="100%"></video>
```

```@setup 1
using Bonito, BonitoWidgets
Bonito.Page()

# A coloured placeholder used throughout the docs to stand in for real content
# (an editor, a plot, a log view, ...).
pl(label, color; min_height="60px") = DOM.div(label;
    style=Styles(
        "display" => "flex", "align-items" => "center", "justify-content" => "center",
        "width" => "100%", "height" => "100%", "min-height" => min_height,
        "background" => color, "color" => "white",
        "font-family" => "var(--bw-font)", "font-size" => "16px"))

# A fixed-height frame so a layout widget has room to render.
frame(content; height="320px") = DOM.div(content;
    style=Styles("height" => height, "border" => "1px solid var(--bw-border)",
                 "border-radius" => "var(--bw-radius)", "overflow" => "hidden"))
```

## Quickstart

```@example 1
using Bonito, BonitoWidgets

App() do
    ws = Workspace(
        Panel("editor", pl("Editor", "#3b82f6"); label="Editor", closable=true),
        Panel("plot",   pl("Plot",   "#8b5cf6"); label="Plot",   closable=true),
        Panel("log",    pl("Log",    "#10b981"); label="Log",    closable=true);
        layout = workspacelayout(
            hsplit(tabgroup("editor", "plot"), tabgroup("log"); fractions=[0.7, 0.3])),
    )
    DOM.div(Theme(), frame(ws))
end
```

Drag a tab to the edge of a group and only that panel splits out; drop it on
another group's tab strip to merge them back. See [Workspace](@ref) for the
full story, or [Components](@ref) for the lighter-weight building blocks.

## Design principles

- **Keep-alive content.** Panels are mounted once and re-flowed with CSS only.
  Switching tabs, flipping a split's orientation, or toggling a `PanelGroup`
  between tabs and splits never re-renders children — WebGL contexts, Makie
  cameras, and widget state survive every layout change.
- **Observables everywhere, bidirectional.** Every piece of layout state
  (active tab, split fraction, orientation, collapsed, window geometry) is an
  `Observable`: user gestures notify Julia, and setting it from Julia updates
  the DOM live.
- **Touch + mouse from one code path.** All drags use pointer events with
  pointer capture; hit areas grow on coarse pointers, and narrow viewports fall
  back to tab layout automatically.
- **Theming via CSS variables.** Every color/metric reads a `--bw-*` variable
  with automatic light/dark defaults. Restyle everything with [`Theme`](@ref),
  or one instance via its `style=Styles(...)` kwarg. See [Theming](@ref).
