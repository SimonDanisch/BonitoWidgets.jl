# Theming

Colors and sizes come from `--bw-*` CSS variables, with light/dark defaults that
follow `prefers-color-scheme`. Restyle every widget with [`Theme`](@ref), or one
widget through its `style=Styles(...)` argument.

```@setup theme
using Bonito, BonitoWidgets
Bonito.Page()
pl(label, color; min_height="60px") = DOM.div(label;
    style=Styles(
        "display" => "flex", "align-items" => "center", "justify-content" => "center",
        "width" => "100%", "height" => "100%", "min-height" => min_height,
        "background" => color, "color" => "white",
        "font-family" => "var(--bw-font)", "font-size" => "16px"))
frame(content; height="180px") = DOM.div(content;
    style=Styles("height" => height, "border" => "1px solid var(--bw-border)",
                 "border-radius" => "var(--bw-radius)", "overflow" => "hidden"))
```

```@docs; canonical=false
Theme
```

`Theme()` with no arguments ships the defaults. Components already include them,
so you only need it to override. Keywords map to variables (`bg_panel` becomes
`--bw-bg-panel`); `scheme=:light` or `:dark` pins the palette instead of
following the OS.

```@example theme
using Bonito, BonitoWidgets

App() do
    tabs() = Tabs("Scene" => pl("Scene", "#1118"), "Log" => pl("Log", "#1118"))
    DOM.div(
        DOM.div(Theme(scheme=:dark, accent="#00d4ff", bg_panel="#0b0f17"), tabs();
            style=Styles("flex"=>"1")),
        DOM.div(Theme(scheme=:light, accent="#e11d48", bg_panel="#ffffff"), tabs();
            style=Styles("flex"=>"1"));
        style=Styles("display"=>"flex", "gap"=>"16px"))
end
```

## Main variables

| Variable | Purpose |
|---|---|
| `--bw-bg`, `--bw-bg-panel`, `--bw-bg-bar`, `--bw-bg-hover` | surfaces |
| `--bw-text`, `--bw-text-muted` | text |
| `--bw-accent`, `--bw-accent-bg` | active tab/grip highlights |
| `--bw-border`, `--bw-radius`, `--bw-shadow` | chrome |
| `--bw-bar-size`, `--bw-gutter-size` | hit-area sizing (grows on touch) |
| `--bw-font`, `--bw-font-size`, `--bw-space-1..4` | typography/spacing |
