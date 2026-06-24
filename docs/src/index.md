The widgets on these pages are real Bonito apps exported into the HTML, so you
can click tabs, drag gutters, and tear panels off. The video shows them driven
from code in a real Electron window (see [Testing layouts](@ref)):

```@raw html
<video src="assets/walkthrough.mp4" controls loop muted width="100%"></video>
```

```@setup 1
using Bonito, BonitoWidgets

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

Drag a tab to the edge of a group and only that panel splits off; drop it on
another group's tab strip to merge them back. See [Workspace](@ref) for the
details, or [Components](@ref) for the smaller building blocks.

## How it works

- Panels are mounted once. Switching tabs, changing a split's orientation, or
  moving a panel between groups re-flows them with CSS and never re-renders the
  children, so WebGL contexts, Makie cameras, and widget state survive.
- Layout state (active tab, split fraction, orientation, collapsed, window
  position) is held in `Observable`s. User actions update them, and writing to
  them from Julia updates the DOM.
- Drags use pointer events, so mouse and touch take the same path. Hit areas
  grow on touch, and narrow windows fall back to tab layout.
- Colors and sizes come from `--bw-*` CSS variables with light/dark defaults.
  Restyle everything with [`Theme`](@ref), or one widget through its
  `style=Styles(...)` argument. See [Theming](@ref).
