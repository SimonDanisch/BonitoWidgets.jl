# The button family: plain `<button>`s (or links) styled by class, so the same
# vocabulary works for buttons built in Julia and in JS.
#
#   bw-btn            filled primary
#   bw-btn-secondary  bordered surface, the default for most controls
#   bw-btn-ghost      borderless
#   bw-btn-danger     the destructive action
#   bw-btn-sm         compact size, for headers and cards
#   bw-btn-loading    work in progress
#
# `Menu` and `Modal` bring these styles along. A page using the classes on its
# own buttons includes `BUTTON_STYLES` once.

"""
    BUTTON_STYLES

Styles for the `bw-btn` class family: `bw-btn` (filled primary) plus the
modifiers `bw-btn-secondary`, `bw-btn-ghost`, `bw-btn-danger`, `bw-btn-sm` and
`bw-btn-loading`. Include it once in a page that uses the classes:

```julia
DOM.div(BUTTON_STYLES,
        DOM.button("Save"; class = "bw-btn"),
        DOM.button("Cancel"; class = "bw-btn bw-btn-secondary"))
```
"""
const BUTTON_STYLES = Styles(
    CSS(".bw-btn",
        "appearance" => "none", "border" => "1px solid transparent",
        "padding" => "6px 12px",
        "border-radius" => "var(--bw-radius-sm)",
        "background" => "var(--bw-accent)", "color" => "var(--bw-accent-fg)",
        "font" => "inherit", "font-size" => "var(--bw-font-size-ui)", "font-weight" => "500",
        "line-height" => "18px",
        "cursor" => "pointer", "text-decoration" => "none",
        # A narrow viewport must not wrap a label like "+ New project" onto two
        # lines inside its button.
        "white-space" => "nowrap",
        "display" => "inline-flex", "align-items" => "center", "gap" => "6px",
        "transition" => "background 120ms ease, transform 80ms ease, opacity 120ms ease, color 120ms"),
    CSS(".bw-btn:hover", "background" => "var(--bw-accent-hover)"),
    CSS(".bw-btn:active", "transform" => "translateY(1px)"),
    CSS(".bw-btn-secondary",
        "background" => "var(--bw-bg-panel)", "color" => "var(--bw-text)",
        "border-color" => "var(--bw-border-strong)"),
    CSS(".bw-btn-secondary:hover", "background" => "var(--bw-bg-subtle)"),
    CSS(".bw-btn-ghost",
        "background" => "transparent", "color" => "var(--bw-text-muted)",
        "padding" => "6px 8px"),
    CSS(".bw-btn-ghost:hover",
        "background" => "var(--bw-bg-subtle)", "color" => "var(--bw-text)"),
    CSS(".bw-btn-danger",
        "background" => "var(--bw-bg-panel)", "color" => "var(--bw-error)",
        "border-color" => "color-mix(in srgb, var(--bw-error) 40%, transparent)"),
    CSS(".bw-btn-danger:hover",
        "background" => "color-mix(in srgb, var(--bw-error) 10%, transparent)"),
    CSS(".bw-btn-loading", "opacity" => "0.7", "cursor" => "wait"),
    CSS(".bw-btn-sm", "padding" => "3px 9px", "font-size" => "var(--bw-font-size-sm)"),
)
