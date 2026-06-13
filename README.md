# BonitoWidgets

Reusable, stylable layout components for [Bonito.jl](https://github.com/SimonDanisch/Bonito.jl):
tabs, resizable splits, VSCode-style panel groups, collapsibles, and floating
windows — optimized for both desktop and mobile.

Distilled from the layout code in ReynKoWebViz, BonitoBook, and BonitoTeam.

## Design principles

- **Keep-alive content.** Panels are mounted once and re-flowed with CSS only.
  Switching tabs, flipping a split's orientation, or toggling a `PanelGroup`
  between tabs and splits never re-renders children — WebGL contexts, Makie
  cameras, and widget state survive every layout change. Size-critical layout
  is set as inline styles, so a WGLMakie figure with `resize_to=:parent`
  always measures real dimensions at init.
- **Observables everywhere, bidirectional.** Every piece of layout state
  (active tab, split fraction, orientation, collapsed, window geometry) is an
  `Observable`: user gestures notify Julia, and setting it from Julia updates
  the DOM live. Pass your own observables into constructors to share state
  between widgets (e.g. one `direction` driving a split and its toggle button).
- **Touch + mouse from one code path.** All drags use pointer events with
  pointer capture. On coarse pointers, bars and resize gutters grow
  (`--bw-bar-size`, `--bw-gutter-size`); tab bars scroll horizontally; below
  700px viewport width `PanelGroup` forces tab layout (splits are unusable on
  phones) and restores the chosen split mode when the viewport widens.
- **Theming via CSS variables.** Every color/metric reads a `--bw-*` variable
  with automatic light/dark defaults (`prefers-color-scheme`). Restyle the
  whole widget set with [`Theme`](#theme), or one instance via its
  `style=Styles(...)` kwarg.

## Components

### Workspace

Full VSCode-style pane/tab management: a **split tree whose leaves are tab
groups**. Drag a tab to the edge of a group and only that panel splits out —
the remaining tabs stay together (`| tabs(Editor, Plot) | Log |`); drop a tab
on another group's strip or center to move it there; a group dissolves when
its last tab leaves. Panel contents are moved between groups, never
re-rendered.

```julia
ws = Workspace("Editor" => ed, "Plot" => fig, "Log" => log)   # starts as one tab group
# or start pre-arranged:
ws = Workspace("Editor" => ed, "Plot" => fig, "Log" => log;
               layout=hsplit(tabgroup(1, 2), tabgroup(3); fractions=[0.7, 0.3]))
on(ws.layout) do tree     # plain JSON-able Dict/Vector tree — persist it
    save_layout(tree)
end
ws.layout[] = saved_tree  # restore an arrangement
```

Use `Workspace` for a main application layout; use `PanelGroup` (below) when
a single flat group — all tabs or all split — is enough.

### Tabs

```julia
tabs = Tabs("3D View" => fig1, "Spectrum" => fig2; active=1, closable=true)
on(tabs.active) do i; @info "switched to tab $i"; end
tabs.active[] = 2          # switch from Julia
on(tabs.closed) do i; @info "tab $i closed"; end
```

### SplitContainer

Two panes with a draggable gutter. Optional per-pane headers with collapse
chevrons.

```julia
split = SplitContainer(left, right;
    direction=:row,           # or :column (:horizontal/:vertical aliases work)
    split=0.4,                # fraction for pane a, Observable, drag-updated
    titles=("Scene", "Controls"),  # nothing (default) → bare panes
    collapsible=true,         # chevron per header; collapsed::Observable{Int} (0/1/2)
    min_fraction=0.08,
)
split.direction[] = :column   # re-flows live, children untouched
```

### PanelGroup

VSCode-style pane management: N named panels shown **as tabs or side by side**,
switched at runtime via the built-in bar widgets (tabs / split-horizontal /
split-vertical / collapse) — or by **dragging a tab into a layout slot**:
drop zones light up over the body (left/right → horizontal split, top/bottom
→ vertical split, center → back to tabs with that panel active), and dropping
on another tab in the strip reorders. Gutters between split panels drag-resize.

```julia
group = PanelGroup("Editor" => ed, "Plot" => fig, "Log" => log;
                   mode=:tabs)        # :tabs, :row, :column
group.mode[] = :row                   # same panels, now side by side
group.order[] = [3, 1, 2]             # display order (drag-updated too)
group.fractions[] = [0.5, 0.3, 0.2]   # per-position sizes, restore a saved layout
group.collapsed[] = true              # fold down to the bar
```

### Collapsible

```julia
Collapsible("Settings", settings_dom; expanded=false)
```

### FloatingWindow

Draggable/resizable fixed-position window, viewport-clamped.

```julia
w = FloatingWindow(tools; title="Tools", x=80, y=80, width=640, height=420)
on(w.close_trigger) do _; w.visible[] = false; end   # caller decides semantics
on(w.x) do x; save_geometry!(...); end               # persist gestures
```

### Small widgets

`IconButton(icon; title, onclick)`, `OrientationToggle(direction_obs)`,
`CollapseButton(collapsed_obs)` — the bar widgets, exported for custom toolbars.

## Theme

```julia
App() do
    DOM.div(
        Theme(scheme=:dark, accent="#00d4ff", bg_panel="#000"),
        my_layout...,
    )
end
```

`Theme()` (no args) just ships the defaults — components include them
automatically, so it's only needed for overrides. Keywords map to variables
(`bg_panel` → `--bw-bg-panel`); `scheme=:light/:dark` pins the palette instead
of following the OS. Main variables:

| Variable | Purpose |
|---|---|
| `--bw-bg`, `--bw-bg-panel`, `--bw-bg-bar`, `--bw-bg-hover` | surfaces |
| `--bw-text`, `--bw-text-muted` | text |
| `--bw-accent`, `--bw-accent-bg` | active tab/grip highlights |
| `--bw-border`, `--bw-radius`, `--bw-shadow` | chrome |
| `--bw-bar-size`, `--bw-gutter-size` | hit-area sizing (auto-grows on touch) |
| `--bw-font`, `--bw-font-size`, `--bw-space-1..4` | typography/spacing |

## Demo

```julia
app = include("examples/demo.jl")
server = Bonito.Server(app, "0.0.0.0", 8765)
```
