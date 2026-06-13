"""
    Collapsible(header, content; expanded=true, style=Styles())

A section that folds its content away. `header` (any renderable) is always
visible; clicking it — or the chevron — toggles the content with a smooth
animation. The content stays mounted while collapsed, so widget state and
WebGL contexts survive.

`expanded::Observable{Bool}` is bidirectional: clicks notify Julia, and
setting it from Julia animates the fold.
"""
struct Collapsible
    header::Any
    content::Any
    expanded::Observable{Bool}
    style::Styles
end

function Collapsible(header, content; expanded::Union{Bool,Observable{Bool}}=true,
                     style=Styles())
    expanded_obs = expanded isa Observable ? expanded : Observable(expanded)
    return Collapsible(header, content, expanded_obs, style)
end

function Bonito.jsrender(session::Session, c::Collapsible)
    init = c.expanded[]
    header = DOM.div(
        DOM.span(icon_chevron_down(); class="bw-collapsible-chevron"),
        DOM.div(c.header; class="bw-collapsible-title");
        class="bw-collapsible-header",
    )
    # The 1fr/0fr grid-row trick animates to "content height" without
    # measuring; the inner div clips during the transition.
    wrap = DOM.div(
        DOM.div(c.content; class="bw-collapsible-content");
        class="bw-collapsible-wrap",
        style=Styles(
            "display" => "grid",
            "grid-template-rows" => init ? "1fr" : "0fr",
            "transition" => "grid-template-rows var(--bw-transition)",
        ),
    )
    wire = js"""
    (() => {
        const header = $(header);
        const wrap = $(wrap);
        const expanded = $(c.expanded);
        const container = header.closest('.bw-collapsible');
        function apply(open) {
            wrap.style.gridTemplateRows = open ? '1fr' : '0fr';
            container.classList.toggle('bw-collapsed', !open);
        }
        header.addEventListener('click', () => expanded.notify(!(expanded.value)));
        expanded.on(apply);
        apply(expanded.value);
    })();
    """
    container = DOM.div(
        THEME_STYLES, COLLAPSIBLE_STYLES,
        header, wrap, DOM.script(wire);
        class=init ? "bw-collapsible" : "bw-collapsible bw-collapsed",
        style=Styles(c.style, "box-sizing" => "border-box"),
    )
    return Bonito.jsrender(session, container)
end

const COLLAPSIBLE_STYLES = Styles(
    CSS(".bw-collapsible",
        "background-color" => "var(--bw-bg-panel)",
        "border" => "1px solid var(--bw-border)",
        "border-radius" => "var(--bw-radius)",
        "overflow" => "hidden",
    ),
    CSS(".bw-collapsible-header",
        "display" => "flex",
        "align-items" => "center",
        "gap" => "var(--bw-space-2)",
        "padding" => "var(--bw-space-2) var(--bw-space-3)",
        "min-height" => "calc(var(--bw-bar-size) * 0.8)",
        "box-sizing" => "border-box",
        "background-color" => "var(--bw-bg-bar)",
        "color" => "var(--bw-text)",
        "font-family" => "var(--bw-font)",
        "font-size" => "var(--bw-font-size)",
        "cursor" => "pointer",
        "user-select" => "none",
        "-webkit-tap-highlight-color" => "transparent",
        "transition" => "background-color var(--bw-transition)",
    ),
    CSS(".bw-collapsible-header:hover", "background-color" => "var(--bw-bg-hover)"),
    CSS(".bw-collapsible-chevron",
        "display" => "flex",
        "line-height" => "0",
        "color" => "var(--bw-text-muted)",
        "transition" => "transform var(--bw-transition)",
    ),
    CSS(".bw-collapsible.bw-collapsed .bw-collapsible-chevron",
        "transform" => "rotate(-90deg)"),
    CSS(".bw-collapsible-title", "flex" => "1 1 auto", "min-width" => "0"),
    CSS(".bw-collapsible-content", "min-height" => "0", "overflow" => "hidden"),
    CSS(".bw-collapsible:not(.bw-collapsed) > .bw-collapsible-header",
        "border-bottom" => "1px solid var(--bw-border)"),
)
