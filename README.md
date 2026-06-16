# BonitoWidgets

![](examples/walkthrough.mp4)

Layout components for [Bonito.jl](https://github.com/SimonDanisch/Bonito.jl):
tabs, resizable splits, VSCode-style panel groups, collapsibles, and floating
windows. They work the same with mouse and touch.

## Walkthrough

The `Workspace` driven from code in a real Electron window: steering plots,
splitting the layout by dragging a tab to a group edge, floating a panel and
docking it back. Recorded with ElectronCall. Source:
[`examples/walkthrough.jl`](examples/walkthrough.jl).

https://github.com/user-attachments/assets/276c5002-a0ce-40ec-8db5-7cf132ea4038

## How it works

- Panels are mounted once. Switching tabs, changing a split's orientation, or
  moving a panel between groups re-flows them with CSS and never re-renders the
  children, so WebGL contexts, Makie cameras, and widget state survive. Sizes
  are set as inline styles, so a WGLMakie figure with `resize_to=:parent`
  measures real dimensions at startup.
- Layout state (active tab, split fraction, orientation, collapsed, window
  position) is held in `Observable`s. User actions update them, and writing to
  them from Julia updates the DOM. Pass your own to share state between widgets,
  e.g. one `direction` for a split and its toggle button.
- Drags use pointer events, so mouse and touch take the same path. Hit areas
  grow on touch (`--bw-bar-size`, `--bw-gutter-size`), tab bars scroll
  sideways, and below 700px `PanelGroup` falls back to tabs, then restores the
  split mode when the window widens.
- Colors and sizes come from `--bw-*` CSS variables with light/dark defaults.
  Restyle everything with [`Theme`](#theme), or one widget through its
  `style=Styles(...)` argument.

## Components

### Workspace

A split tree whose leaves are tab groups. Drag a tab to the edge of a group and
only that panel splits off; the rest stay together. Drop a tab on another
group's tab strip or center to move it there. A group disappears when its last
tab leaves. Moving a panel never re-renders it.

```julia
ws = Workspace("Editor" => ed, "Plot" => fig, "Log" => log)   # starts as one tab group
# or start pre-arranged:
ws = Workspace("Editor" => ed, "Plot" => fig, "Log" => log;
               layout=hsplit(tabgroup(1, 2), tabgroup(3); fractions=[0.7, 0.3]))
on(ws.layout) do tree     # plain Dict/Vector tree, JSON-able
    save_layout(tree)
end
ws.layout[] = saved_tree  # restore an arrangement
```

Use `Workspace` for the main layout. Use `PanelGroup` (below) for a single
group that is either all tabs or all split.

### Tabs

```julia
tabs = Tabs("3D View" => fig1, "Spectrum" => fig2; active=1, closable=true)
on(tabs.active) do i; @info "switched to tab $i"; end
tabs.active[] = 2          # switch from Julia
on(tabs.closed) do i; @info "tab $i closed"; end
```

### SplitContainer

Two panes with a draggable gutter. Optional headers with a collapse chevron per
pane.

```julia
split = SplitContainer(left, right;
    direction=:row,           # or :column (:horizontal/:vertical aliases work)
    split=0.4,                # fraction for pane a, an Observable, drag-updated
    titles=("Scene", "Controls"),  # nothing (default) = bare panes
    collapsible=true,         # chevron per header; collapsed::Observable{Int} (0/1/2)
    min_fraction=0.08,
)
split.direction[] = :column   # re-flows live, children untouched
```

### PanelGroup

N named panels shown as tabs or side by side. Switch with the bar widgets (tabs,
split-horizontal, split-vertical, collapse), or drag a tab into the body: the
left/right edges make a horizontal split, top/bottom make a vertical split, the
center goes back to tabs, and dropping on another tab in the strip reorders.
Gutters between split panels drag to resize.

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

A draggable, resizable, fixed-position window, kept inside the viewport.

```julia
w = FloatingWindow(tools; title="Tools", x=80, y=80, width=640, height=420)
on(w.close_trigger) do _; w.visible[] = false; end   # caller decides what close means
on(w.x) do x; save_geometry!(...); end               # persist gestures
```

### Small widgets

`IconButton(icon; title, onclick)`, `OrientationToggle(direction_obs)`, and
`CollapseButton(collapsed_obs)`: the bar widgets, exported for custom toolbars.

## Theme

```julia
App() do
    DOM.div(
        Theme(scheme=:dark, accent="#00d4ff", bg_panel="#000"),
        my_layout...,
    )
end
```

`Theme()` with no arguments ships the defaults. Components already include them,
so you only need it to override. Keywords map to variables (`bg_panel` becomes
`--bw-bg-panel`); `scheme=:light` or `:dark` pins the palette instead of
following the OS.

| Variable | Purpose |
|---|---|
| `--bw-bg`, `--bw-bg-panel`, `--bw-bg-bar`, `--bw-bg-hover` | surfaces |
| `--bw-text`, `--bw-text-muted` | text |
| `--bw-accent`, `--bw-accent-bg` | active tab/grip highlights |
| `--bw-border`, `--bw-radius`, `--bw-shadow` | chrome |
| `--bw-bar-size`, `--bw-gutter-size` | hit-area sizing (grows on touch) |
| `--bw-font`, `--bw-font-size`, `--bw-space-1..4` | typography/spacing |

## Testing layouts

The video above is driven by a few unexported probe helpers. The layout moves as
panels split and float, so tests can't use fixed pixels. Each probe builds a
small JavaScript expression that finds a point on a widget by its label and
returns `[x, y]`, or `null` if nothing matches:

- `tab(label)`: the tab button whose label starts with `label`
- `groupbody(label; rel=(0.5, 0.9))`: a point in the body of the group that
  holds that tab (the edges are the drop zones for splitting)
- `floattitle(label)`: the title bar of the floating window named `label`

The helpers only use the widgets' CSS classes, so they don't pull in a test
driver. Any driver that can run JS and return a point can use them. With
[ElectronCall](https://github.com/SimonDanisch/ElectronCall.jl), wrap the
expression in its `JS` target and pass it to the event DSL:

```julia
using BonitoWidgets: tab, groupbody, floattitle
using ElectronCall.Testing      # JS, Click, Drag, play, ...

play(ctx, [
    Click(JS(tab("Waveform"))),                                       # switch tabs
    Drag(JS(tab("Field")), JS(groupbody("Field"; rel=(0.5, 0.9)))),   # split off the bottom
    Drag(JS(floattitle("Surface")), JS(tab("Phase Portrait"))),       # dock a floating window
])
```

## Demo

```julia
app = include("examples/demo.jl")
server = Bonito.Server(app, "0.0.0.0", 8765)
```
