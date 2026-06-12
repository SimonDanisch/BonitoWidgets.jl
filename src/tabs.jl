"""
    Tabs(items...; active=1, closable=false, style=Styles())
    Tabs("3D View" => fig, "Spectrum" => fig2; active=1)

A tabbed container switching between named panels. Each item is a
`label => content` pair; the label can be a string or any renderable, the
content typically a widget or a WGLMakie figure wrapped with
`resize_to=:parent`.

All panels stay mounted, stacked via absolute positioning, and only the active
one is visible. Hidden panels keep their full size, so WebGL contexts, Makie
cameras, and widget state survive every switch (no re-render on tab change).

- `active::Observable{Int}` — 1-based index of the shown tab. Bidirectional:
  clicks update it, and setting it from Julia switches the tab.
- `closable` — adds a close button per tab. Closing hides the tab + panel and
  notifies `closed::Observable{Int}` with the index; the content stays mounted
  so you can react however you like (or ignore it).

The tab bar scrolls horizontally when tabs overflow (touch-friendly), and tab
height follows `--bw-bar-size`, which grows on coarse pointers.
"""
struct Tabs
    labels::Vector{Any}
    contents::Vector{Any}
    active::Observable{Int}
    closable::Bool
    closed::Observable{Int}
    style::Styles
end

function Tabs(items::AbstractVector{<:Pair}; active::Integer=1, closable::Bool=false,
              style=Styles())
    isempty(items) && throw(ArgumentError("Tabs needs at least one tab"))
    n = length(items)
    1 ≤ active ≤ n || throw(ArgumentError("active=$active out of range 1:$n"))
    labels = Any[p.first for p in items]
    contents = Any[p.second for p in items]
    return Tabs(labels, contents, Observable(Int(active)), closable, Observable(0), style)
end
Tabs(items::Pair...; kwargs...) = Tabs(collect(items); kwargs...)

function Bonito.jsrender(session::Session, t::Tabs)
    n = length(t.labels)
    init = t.active[]

    tab_buttons = map(1:n) do i
        children = Any[DOM.span(t.labels[i]; class="bw-tab-label")]
        if t.closable
            push!(children, DOM.span(icon_close(); class="bw-tab-close", title="Close"))
        end
        DOM.button(children...; class=(i == init ? "bw-tab bw-active" : "bw-tab"))
    end
    tab_bar = DOM.div(
        tab_buttons...;
        class="bw-tab-bar",
        style=Styles("display" => "flex", "flex" => "0 0 auto"),
    )

    # Panels: all mounted, stacked absolutely; visibility is the only thing
    # that changes on switch. Sizing stays inline so wrapped canvases measure
    # real dimensions at init, independent of stylesheet timing.
    panel_style(active::Bool) = Styles(
        "position" => "absolute", "inset" => "0",
        "visibility" => active ? "visible" : "hidden",
        "pointer-events" => active ? "auto" : "none",
    )
    panels = [
        DOM.div(t.contents[i];
                class=(i == init ? "bw-tab-panel bw-active" : "bw-tab-panel"),
                style=panel_style(i == init))
        for i in 1:n
    ]
    tab_panels = DOM.div(
        panels...;
        class="bw-tab-panels",
        style=Styles(
            "position" => "relative",
            "flex" => "1 1 0",
            "min-width" => "0", "min-height" => "0",
            "overflow" => "hidden",
        ),
    )

    # Bidirectional: click → apply locally + notify Julia; Julia → apply.
    # Close hides the tab and hands focus to the nearest open neighbor.
    switch_script = js"""
    (() => {
        const active = $(t.active);
        const closed = $(t.closed);
        const bar = $(tab_bar);
        const wrapper = $(tab_panels);
        const buttons = Array.from(bar.querySelectorAll('.bw-tab'));
        const panels = Array.from(wrapper.querySelectorAll('.bw-tab-panel'));
        const n = buttons.length;
        function apply(idx) {
            idx = Math.max(1, Math.min(n, idx | 0));
            for (let i = 0; i < n; i++) {
                const on = (i + 1) === idx;
                buttons[i].classList.toggle('bw-active', on);
                const p = panels[i];
                p.classList.toggle('bw-active', on);
                p.style.visibility = on ? 'visible' : 'hidden';
                p.style.pointerEvents = on ? 'auto' : 'none';
            }
        }
        buttons.forEach((b, i) => {
            b.addEventListener('click', () => {
                if (b.classList.contains('bw-closed')) return;
                apply(i + 1);
                active.notify(i + 1);
            });
            const closeBtn = b.querySelector('.bw-tab-close');
            if (closeBtn) closeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                b.classList.add('bw-closed');
                panels[i].style.visibility = 'hidden';
                panels[i].style.pointerEvents = 'none';
                if (b.classList.contains('bw-active')) {
                    const open = buttons.findIndex(x => !x.classList.contains('bw-closed'));
                    if (open >= 0) { apply(open + 1); active.notify(open + 1); }
                }
                closed.notify(i + 1);
            });
        });
        active.on(apply);
    })();
    """

    container = DOM.div(
        THEME_STYLES, TABS_STYLES,
        tab_bar, tab_panels, DOM.script(switch_script);
        class="bw-tabs",
        style=Styles(t.style,
            "display" => "flex",
            "flex-direction" => "column",
            "width" => "100%", "height" => "100%",
            "min-width" => "0", "min-height" => "0",
            "box-sizing" => "border-box",
        ),
    )
    return Bonito.jsrender(session, container)
end

const TABS_STYLES = Styles(
    CSS(".bw-tab-bar",
        "background-color" => "var(--bw-bg-bar)",
        "border-bottom" => "1px solid var(--bw-border)",
        "min-height" => "var(--bw-bar-size)",
        "overflow-x" => "auto",
        "overflow-y" => "hidden",
        "scrollbar-width" => "none",
        "-webkit-overflow-scrolling" => "touch",
    ),
    CSS(".bw-tab-bar::-webkit-scrollbar", "display" => "none"),
    CSS(".bw-tab",
        "display" => "inline-flex",
        "align-items" => "center",
        "gap" => "var(--bw-space-2)",
        "padding" => "0 var(--bw-space-3)",
        "background" => "transparent",
        "border" => "none",
        "border-right" => "1px solid var(--bw-border)",
        "color" => "var(--bw-text-muted)",
        "font-family" => "var(--bw-font)",
        "font-size" => "var(--bw-font-size-sm)",
        "white-space" => "nowrap",
        "cursor" => "pointer",
        "transition" => "color var(--bw-transition), background-color var(--bw-transition)",
        "user-select" => "none",
        "-webkit-tap-highlight-color" => "transparent",
    ),
    CSS(".bw-tab:hover",
        "color" => "var(--bw-text)",
        "background-color" => "var(--bw-bg-hover)",
    ),
    CSS(".bw-tab.bw-active",
        "color" => "var(--bw-accent)",
        "background-color" => "var(--bw-accent-bg)",
        "box-shadow" => "inset 0 -2px 0 var(--bw-accent)",
    ),
    CSS(".bw-tab.bw-closed", "display" => "none"),
    CSS(".bw-tab-close",
        "display" => "inline-flex",
        "align-items" => "center",
        "border-radius" => "var(--bw-radius-sm)",
        "padding" => "2px",
        "opacity" => "0.5",
        "transition" => "opacity var(--bw-transition), background-color var(--bw-transition)",
    ),
    CSS(".bw-tab-close:hover",
        "opacity" => "1",
        "background-color" => "var(--bw-bg-hover)",
    ),
    CSS(".bw-tab-panels", "background-color" => "var(--bw-bg-panel)"),
)
