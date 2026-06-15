# Workspace

```@setup ws
using Bonito, BonitoWidgets
Bonito.Page()
pl(label, color; min_height="60px") = DOM.div(label;
    style=Styles(
        "display" => "flex", "align-items" => "center", "justify-content" => "center",
        "width" => "100%", "height" => "100%", "min-height" => min_height,
        "background" => color, "color" => "white",
        "font-family" => "var(--bw-font)", "font-size" => "16px"))
frame(content; height="340px") = DOM.div(content;
    style=Styles("height" => height, "border" => "1px solid var(--bw-border)",
                 "border-radius" => "var(--bw-radius)", "overflow" => "hidden"))
```

A split tree whose leaves are tab groups. Drag a tab to the edge of a group and
only that panel splits off; the rest stay together. Drop a tab on another
group's tab strip or center to move it there. A group disappears when its last
tab leaves. Drag a tab out of the docked area to float it, and drag a floating
window's title bar back onto a group (or use its dock button) to dock it again.
Panels are moved between groups, never re-rendered.

```@docs; canonical=false
Workspace
```

Drag the tabs around, split the layout, or tear off the floating Surface:

```@example ws
using Bonito, BonitoWidgets

App() do
    ws = Workspace(
        Panel("controls", pl("Controls", "#1f2937"); label="Controls", closable=false),
        Panel("phase",    pl("Phase Portrait", "#3b82f6"); label="Phase Portrait", closable=true),
        Panel("wave",     pl("Waveform", "#8b5cf6"); label="Waveform", closable=true),
        Panel("field",    pl("Field", "#0ea5e9"); label="Field", closable=true),
        Panel("surface",  pl("Surface", "#7c3aed"); label="Surface", closable=true);
        layout = workspacelayout(
            hsplit(tabgroup("controls"),
                   tabgroup("phase", "wave", "field"; active="phase"); fractions=[0.26, 0.74]);
            floating=[floatpanel("surface"; x=520, y=30, width=240, height=180)]),
    )
    DOM.div(Theme(), frame(ws))
end
```

## Building a layout

The starting arrangement is built from a handful of constructors:

```@docs; canonical=false
workspacelayout
tabgroup
hsplit
vsplit
floatpanel
Panel
```

## Persisting and restoring

`ws.layout` is a plain `Dict`/`Vector` tree (floats included), and it is
JSON-able. Listen to it with `on` to save rearrangements; assign to it to
restore one:

```julia
on(ws.layout) do tree
    save_layout(tree)         # store the Dict somewhere
end
ws.layout[] = saved_tree      # re-flows the DOM live, children untouched
```

## Driving it from Julia

Add, remove, float, dock and activate panels imperatively:

```@docs; canonical=false
add_panel!
remove_panel!
float_panel!
dock_panel!
activate_panel!
```
