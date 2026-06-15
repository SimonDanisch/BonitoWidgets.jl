# Components

Smaller building blocks, for when a full [Workspace](@ref) is more than you
need.

```@setup comp
using Bonito, BonitoWidgets
Bonito.Page()
pl(label, color; min_height="60px") = DOM.div(label;
    style=Styles(
        "display" => "flex", "align-items" => "center", "justify-content" => "center",
        "width" => "100%", "height" => "100%", "min-height" => min_height,
        "background" => color, "color" => "white",
        "font-family" => "var(--bw-font)", "font-size" => "16px"))
frame(content; height="200px") = DOM.div(content;
    style=Styles("height" => height, "border" => "1px solid var(--bw-border)",
                 "border-radius" => "var(--bw-radius)", "overflow" => "hidden"))
```

## Tabs

Tabs with no docking, optionally closable. `active` and `closed` are observables
you can read or set from Julia.

```@docs; canonical=false
Tabs
```

```@example comp
using Bonito, BonitoWidgets

App() do
    tabs = Tabs(
        "First"  => pl("First tab",  "#0ea5e9"),
        "Second" => pl("Second tab", "#64748b"),
        "Third"  => pl("Third tab",  "#dc2626");
        closable = true,
    )
    DOM.div(Theme(), frame(tabs; height="160px"))
end
```

## SplitContainer

Two panes with a draggable gutter, optional headers with a collapse chevron per
pane. The orientation is an `Observable`; change it and the panes re-flow
without re-rendering their children.

```@docs; canonical=false
SplitContainer
```

```@example comp
using Bonito, BonitoWidgets

App() do
    split = SplitContainer(
        pl("Scene", "#f59e0b"), pl("Controls", "#ef4444");
        titles = ("Scene", "Controls"), split = 0.4, collapsible = true,
    )
    DOM.div(
        Theme(),
        DOM.div("Toggle orientation:", OrientationToggle(split.direction);
            style=Styles("display"=>"flex","gap"=>"8px","align-items"=>"center",
                         "margin-bottom"=>"8px","font-family"=>"var(--bw-font)")),
        frame(split),
    )
end
```

## PanelGroup

A single group of N named panels, shown as tabs or side by side. Switch with the
bar widgets, or drag a tab into the body: the edges make a split, the center
goes back to tabs.

```@docs; canonical=false
PanelGroup
```

```@example comp
using Bonito, BonitoWidgets

App() do
    group = PanelGroup(
        "Scene"    => pl("Scene", "#0ea5e9"),
        "Spectrum" => pl("Spectrum", "#dc2626"),
        "Timeline" => pl("Timeline", "#64748b");
        mode = :tabs,
    )
    DOM.div(Theme(), frame(group; height="240px"))
end
```

## Collapsible

```@docs; canonical=false
Collapsible
```

```@example comp
using Bonito, BonitoWidgets

App() do
    DOM.div(Theme(),
        Collapsible("Settings", pl("Hidden content", "#475569"); expanded=true),
        Collapsible("Advanced", pl("More content", "#334155"); expanded=false))
end
```

## FloatingWindow

A draggable, resizable, fixed-position window, kept inside the viewport. Below it
sits in a positioned frame so it stays in the page; in a real app it floats over
the whole viewport.

```@docs; canonical=false
FloatingWindow
```

```@example comp
using Bonito, BonitoWidgets

App() do
    win = FloatingWindow(pl("Drag my title bar", "#7c3aed");
        title="Tools", x=40, y=30, width=260, height=170)
    DOM.div(Theme(),
        DOM.div(win;
            style=Styles("position"=>"relative", "transform"=>"translateZ(0)",
                         "height"=>"240px", "overflow"=>"hidden",
                         "border"=>"1px solid var(--bw-border)",
                         "border-radius"=>"var(--bw-radius)")))
end
```

## Small widgets

The bar widgets, exported for custom toolbars:

```@docs; canonical=false
IconButton
OrientationToggle
CollapseButton
```
