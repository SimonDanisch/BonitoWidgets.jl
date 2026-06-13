# Small chrome widgets: a generic icon button plus the two stateful toggles
# (orientation flip, collapse chevron) that the layout containers use — also
# exported so apps can place them in their own toolbars.

const ICON_BUTTON_STYLES = Styles(
    CSS(".bw-icon-btn",
        "display" => "inline-flex",
        "align-items" => "center",
        "justify-content" => "center",
        "width" => "calc(var(--bw-bar-size) - 8px)",
        "height" => "calc(var(--bw-bar-size) - 8px)",
        "padding" => "0",
        "flex" => "0 0 auto",
        "background" => "transparent",
        "border" => "none",
        "border-radius" => "var(--bw-radius-sm)",
        "color" => "var(--bw-text-muted)",
        "font-size" => "var(--bw-font-size)",
        "cursor" => "pointer",
        "transition" => "all var(--bw-transition)",
        "-webkit-tap-highlight-color" => "transparent",
    ),
    CSS(".bw-icon-btn:hover",
        "background-color" => "var(--bw-bg-hover)",
        "color" => "var(--bw-text)",
    ),
    CSS(".bw-icon-btn.bw-active",
        "color" => "var(--bw-accent)",
        "background-color" => "var(--bw-accent-bg)",
    ),
    CSS(".bw-icon-btn > svg", "transition" => "transform var(--bw-transition)"),
)

"""
    IconButton(icon; title="", onclick=nothing, style=Styles())

A small square icon button matching the widget chrome (hover/active states,
touch-friendly sizing). `icon` is any renderable (the `icon_*` helpers in this
package return inline SVGs); `onclick` takes a `js"..."` handler.
"""
function IconButton(icon; title::String="", onclick=nothing, style=Styles())
    attributes = Dict{Symbol,Any}(:class => "bw-icon-btn", :title => title)
    isnothing(onclick) || (attributes[:onclick] = onclick)
    return DOM.button(ICON_BUTTON_STYLES, icon; style=style, attributes...)
end

# Symbol observables can't be notified from JS (strings don't convert), so the
# layout widgets bridge them to a linked String observable for the wire.
function string_bridge(obs::Observable{Symbol})
    str = Observable(string(obs[]))
    on(obs) do v
        s = string(v)
        str[] == s || (str[] = s)
    end
    on(str) do s
        v = Symbol(s)
        obs[] == v || (obs[] = v)
    end
    return str
end

"""
    OrientationToggle(direction::Observable{Symbol}; title="Toggle split direction")

An icon button that flips `direction` between `:row` and `:column`. The icon
always previews the layout the click switches to. Wire the same observable
into a [`SplitContainer`](@ref) (or use `PanelGroup`, which has the toggle
built in).
"""
struct OrientationToggle
    direction::Observable{Symbol}
    title::String
end
OrientationToggle(direction::Observable{Symbol}; title="Toggle split direction") =
    OrientationToggle(direction, title)

function Bonito.jsrender(session::Session, t::OrientationToggle)
    dir_str = string_bridge(t.direction)
    # Both icons are mounted; `data-dir` on the button shows the one that
    # previews the *other* orientation.
    btn = DOM.button(
        ICON_BUTTON_STYLES, ORIENTATION_TOGGLE_STYLES,
        DOM.span(icon_split_row(); class="bw-orient-row"),
        DOM.span(icon_split_column(); class="bw-orient-column");
        class="bw-icon-btn bw-orient-toggle", title=t.title,
        var"data-dir"=string(t.direction[]),
    )
    wire = js"""
    (() => {
        const btn = $(btn);
        const dir = $(dir_str);
        dir.on((d) => { btn.dataset.dir = d; });
        btn.addEventListener('click', () => {
            dir.notify(btn.dataset.dir === 'row' ? 'column' : 'row');
        });
    })();
    """
    return Bonito.jsrender(session, DOM.span(btn, DOM.script(wire); style=Styles("display" => "contents")))
end

const ORIENTATION_TOGGLE_STYLES = Styles(
    CSS(".bw-orient-toggle > span", "display" => "none", "line-height" => "0"),
    # Show the icon of the orientation a click switches to.
    CSS(".bw-orient-toggle[data-dir='row'] > .bw-orient-column", "display" => "block"),
    CSS(".bw-orient-toggle[data-dir='column'] > .bw-orient-row", "display" => "block"),
)

"""
    CollapseButton(collapsed::Observable{Bool}; title="Collapse / expand")

A chevron icon button that toggles `collapsed`; the chevron rotates to point
sideways while collapsed. Wire the observable to whatever should collapse
(e.g. a [`Collapsible`](@ref)'s `expanded` via `!`, or a `PanelGroup`'s
`collapsed`).
"""
struct CollapseButton
    collapsed::Observable{Bool}
    title::String
end
CollapseButton(collapsed::Observable{Bool}; title="Collapse / expand") =
    CollapseButton(collapsed, title)

function Bonito.jsrender(session::Session, c::CollapseButton)
    btn = DOM.button(
        ICON_BUTTON_STYLES, COLLAPSE_BUTTON_STYLES,
        icon_chevron_down();
        class=c.collapsed[] ? "bw-icon-btn bw-collapse-btn bw-collapsed" : "bw-icon-btn bw-collapse-btn",
        title=c.title,
    )
    wire = js"""
    (() => {
        const btn = $(btn);
        const collapsed = $(c.collapsed);
        collapsed.on((v) => btn.classList.toggle('bw-collapsed', v));
        btn.addEventListener('click', () => collapsed.notify(!btn.classList.contains('bw-collapsed')));
    })();
    """
    return Bonito.jsrender(session, DOM.span(btn, DOM.script(wire); style=Styles("display" => "contents")))
end

const COLLAPSE_BUTTON_STYLES = Styles(
    CSS(".bw-collapse-btn.bw-collapsed > svg", "transform" => "rotate(-90deg)"),
)
