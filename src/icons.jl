# Small inline-SVG icon set used by the widget chrome (mode toggles, collapse
# chevrons, close buttons). All icons draw with `currentColor`, so they follow
# the surrounding text/button color and need no theming of their own.

using Bonito: SVG

function icon_svg(children...; viewbox="0 0 16 16")
    return SVG.svg(children...;
        viewBox=viewbox, width="1em", height="1em",
        fill="none", stroke="currentColor",
        var"stroke-width"="1.3", var"stroke-linecap"="round",
        var"stroke-linejoin"="round",
        var"aria-hidden"="true",
    )
end

# A window with a tab strip: outer frame, strip divider, one tab separator.
icon_tabs() = icon_svg(
    SVG.rect(x="1.5", y="2.5", width="13", height="11", rx="1.5"),
    SVG.path(d="M1.5 6.5h13"),
    SVG.path(d="M7 2.5v4"),
)

# Two panes side by side (split along a vertical border).
icon_split_row() = icon_svg(
    SVG.rect(x="1.5", y="2.5", width="13", height="11", rx="1.5"),
    SVG.path(d="M8 2.5v11"),
)

# Two panes stacked (split along a horizontal border).
icon_split_column() = icon_svg(
    SVG.rect(x="1.5", y="2.5", width="13", height="11", rx="1.5"),
    SVG.path(d="M1.5 8h13"),
)

icon_chevron_down() = icon_svg(SVG.path(d="M4 6l4 4 4-4"))

icon_close() = icon_svg(SVG.path(d="M4 4l8 8M12 4l-8 8"))
