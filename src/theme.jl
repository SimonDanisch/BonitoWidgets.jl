# Theming: every visual property of every widget reads a `--bw-*` CSS variable,
# so apps restyle the whole widget set by overriding variables — no per-widget
# styling needed (though every component also accepts `style=Styles(...)` for
# one-off tweaks). Defaults follow the OS via `prefers-color-scheme`; `Theme`
# can force a scheme and/or override individual variables.

# Palettes are plain pair-vectors so `Theme` can re-emit them with higher
# specificity when a scheme is forced.
const LIGHT_PALETTE = [
    "--bw-bg" => "#f4f4f5",
    "--bw-bg-panel" => "#ffffff",
    "--bw-bg-bar" => "#ececee",
    "--bw-bg-hover" => "rgba(0, 0, 0, 0.06)",
    "--bw-text" => "#1f2328",
    "--bw-text-muted" => "#6b7280",
    "--bw-accent" => "#0969da",
    "--bw-accent-bg" => "rgba(9, 105, 218, 0.10)",
    "--bw-border" => "rgba(0, 0, 0, 0.12)",
    "--bw-shadow" => "0 6px 24px rgba(0, 0, 0, 0.18)",
    # Controls (buttons, menus, modals): a quieter surface for hover and
    # secondary areas, a stronger border for popovers, faint text for hints,
    # text on the filled accent, status colors, small shadows and the backdrop
    # behind a modal.
    "--bw-bg-subtle" => "#f9f9fa",
    "--bw-border-strong" => "rgba(0, 0, 0, 0.2)",
    "--bw-text-faint" => "#9ca3af",
    "--bw-accent-hover" => "#0858b9",
    "--bw-accent-fg" => "#ffffff",
    "--bw-success" => "#1a7f37",
    "--bw-error" => "#cf222e",
    "--bw-warning" => "#9a6700",
    "--bw-shadow-sm" => "0 1px 2px rgba(0, 0, 0, 0.06)",
    "--bw-shadow-md" => "0 4px 12px rgba(0, 0, 0, 0.10)",
    "--bw-backdrop" => "rgba(0, 0, 0, 0.35)",
]

const DARK_PALETTE = [
    "--bw-bg" => "#18181b",
    "--bw-bg-panel" => "#1e1e22",
    "--bw-bg-bar" => "#242429",
    "--bw-bg-hover" => "rgba(255, 255, 255, 0.07)",
    "--bw-text" => "#e4e4e7",
    "--bw-text-muted" => "#9a9aa3",
    "--bw-accent" => "#4daafc",
    "--bw-accent-bg" => "rgba(77, 170, 252, 0.12)",
    "--bw-border" => "rgba(255, 255, 255, 0.12)",
    "--bw-shadow" => "0 6px 24px rgba(0, 0, 0, 0.5)",
    "--bw-bg-subtle" => "#222226",
    "--bw-border-strong" => "rgba(255, 255, 255, 0.2)",
    "--bw-text-faint" => "#71717a",
    "--bw-accent-hover" => "#79bdfd",
    "--bw-accent-fg" => "#ffffff",
    "--bw-success" => "#3fb950",
    "--bw-error" => "#f85149",
    "--bw-warning" => "#d29922",
    "--bw-shadow-sm" => "0 1px 2px rgba(0, 0, 0, 0.4)",
    "--bw-shadow-md" => "0 4px 12px rgba(0, 0, 0, 0.45)",
    "--bw-backdrop" => "rgba(0, 0, 0, 0.6)",
]

# Scheme-independent metrics. `--bw-bar-size` and `--bw-gutter-size` grow on
# coarse (touch) pointers so tabs and resize gutters stay comfortably tappable
# on mobile without bloating the desktop look.
const METRIC_VARS = [
    "--bw-font" => "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif",
    # Type scale, by role. Text sizes come from here; only a size that fits a
    # symbol (a caret, an arrow, a ×) to its box is written out.
    "--bw-font-size-xl" => "1.375rem",   # 22px page headings
    "--bw-font-size-lg" => "1rem",       # 16px titles of dialogs and panels
    "--bw-font-size" => "0.875rem",      # 14px body text
    "--bw-font-size-ui" => "0.8125rem",  # 13px controls, secondary text
    "--bw-font-size-sm" => "0.75rem",    # 12px small text: meta lines, paths, previews
    "--bw-font-size-xs" => "0.6875rem",  # 11px labels, captions, hints, timers
    "--bw-font-size-2xs" => "0.625rem",  # 10px badges, counters
    "--bw-radius" => "8px",
    "--bw-radius-sm" => "4px",
    "--bw-space-1" => "4px",
    "--bw-space-2" => "8px",
    "--bw-space-3" => "12px",
    "--bw-space-4" => "16px",
    "--bw-space-5" => "24px",
    "--bw-space-6" => "32px",
    "--bw-bar-size" => "32px",
    "--bw-gutter-size" => "9px",
    "--bw-transition" => "0.15s ease",
    "--bw-z-float" => "1000",
]

const THEME_STYLES = Styles(
    CSS(":root", METRIC_VARS..., LIGHT_PALETTE...),
    CSS("@media (prefers-color-scheme: dark)", CSS(":root", DARK_PALETTE...)),
    CSS("@media (pointer: coarse)",
        CSS(":root",
            "--bw-bar-size" => "42px",
            "--bw-gutter-size" => "14px",
        ),
    ),
)

"""
    Theme(; scheme=:auto, vars...)

Returns a `Styles` overriding the BonitoWidgets CSS variables. Place it
anywhere in your app's DOM (after-the-fact, it wins over the built-in defaults
via selector specificity).

- `scheme` — `:auto` (follow OS, default), `:light`, or `:dark` to force one.
- `vars` — keyword overrides for individual variables; underscores map to
  dashes, e.g. `accent="#00d4ff"` sets `--bw-accent`,
  `bg_panel="black"` sets `--bw-bg-panel`.

```julia
app = App() do
    DOM.div(Theme(scheme=:dark, accent="#00d4ff"), my_widgets...)
end
```
"""
function Theme(; scheme::Symbol=:auto, vars...)
    scheme in (:auto, :light, :dark) ||
        throw(ArgumentError("scheme must be :auto, :light or :dark, got :$scheme"))
    overrides = ["--bw-" * replace(string(k), '_' => '-') => string(v) for (k, v) in vars]
    # `:root:root` outranks the plain `:root` defaults (and their media-query
    # variants) regardless of stylesheet order.
    css = CSS[]
    if scheme === :light
        push!(css, CSS(":root:root", LIGHT_PALETTE...))
    elseif scheme === :dark
        push!(css, CSS(":root:root", DARK_PALETTE...))
    end
    isempty(overrides) || push!(css, CSS(":root:root", overrides...))
    return Styles(THEME_STYLES, css...)
end
