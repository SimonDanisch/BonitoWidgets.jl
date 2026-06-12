"""
    SplitContainer(a, b; direction=:row, split=0.5, titles=nothing,
                   collapsible=true, min_fraction=0.08, style=Styles())

A resizable two-pane container with a draggable gutter between the children:

    direction = :row     [ A │ B ]   drag the vertical gutter to resize widths
    direction = :column  [ A ]       drag the horizontal gutter to resize heights
                         [─┼─]
                         [ B ]

All state is observable and bidirectional (user gestures notify Julia, Julia
updates apply live):

- `direction::Observable{Symbol}` — `:row` or `:column`; flipping it re-flows
  the same DOM (children are never re-rendered). `:horizontal`/`:vertical`
  are accepted as aliases. Pair with [`OrientationToggle`](@ref).
- `split::Observable{Float64}` — fraction (0–1) of the axis given to pane `a`,
  notified at the end of each drag.
- `collapsed::Observable{Int}` — `0` (none), `1`, or `2`: that pane collapses
  to just its header, handing its space to the sibling.

`titles=("A title", "B title")` adds a slim header bar per pane; with
`collapsible=true` each header carries a collapse chevron. `titles=nothing`
(default) renders bare panes — collapsing then only works via the observable.

Drags use pointer events (mouse + touch) and the gutter hit area follows
`--bw-gutter-size`, which grows on coarse pointers. Double-click resets the
split to its initial value. Children fill their pane, so a Makie figure with
`resize_to=:parent` tracks the pane size live while dragging.
"""
struct SplitContainer
    a::Any
    b::Any
    direction::Observable{Symbol}
    split::Observable{Float64}
    titles::Union{Nothing,Tuple{String,String}}
    collapsible::Bool
    collapsed::Observable{Int}
    min_fraction::Float64
    style::Styles
end

function normalize_direction(dir::Symbol)
    dir in (:horizontal, :row) && return :row
    dir in (:vertical, :column) && return :column
    throw(ArgumentError("direction must be :row/:horizontal or :column/:vertical, got :$dir"))
end

function SplitContainer(a, b;
                        direction::Union{Symbol,Observable{Symbol}}=:row,
                        split::Union{Real,Observable{Float64}}=0.5,
                        titles=nothing,
                        collapsible::Bool=true,
                        collapsed::Union{Integer,Observable{Int}}=0,
                        min_fraction::Real=0.08,
                        style=Styles())
    dir_obs = direction isa Observable ? direction : Observable(normalize_direction(direction))
    dir_obs[] = normalize_direction(dir_obs[])
    split_obs = split isa Observable ? split : Observable(Float64(split))
    collapsed_obs = collapsed isa Observable ? collapsed : Observable(Int(collapsed))
    titles_t = isnothing(titles) ? nothing : (String(titles[1]), String(titles[2]))
    return SplitContainer(a, b, dir_obs, split_obs, titles_t, collapsible,
                          collapsed_obs, Float64(min_fraction), style)
end

function split_pane_header(title::String, collapsible::Bool)
    items = Any[DOM.span(title; class="bw-split-title")]
    if collapsible
        push!(items, DOM.button(DOM.span(icon_chevron_down(); class="bw-split-chevron");
                                class="bw-split-collapse", title="Collapse / expand"))
    end
    return DOM.div(items...; class="bw-split-header")
end

function Bonito.jsrender(session::Session, sc::SplitContainer)
    is_row = sc.direction[] === :row
    init_split = round(sc.split[] * 100; digits=3)
    dir_str = string_bridge(sc.direction)

    # Pane A's basis follows `--bw-split-a` (updated live while dragging);
    # pane B fills the rest.
    flex_a = "0 0 var(--bw-split-a, $(init_split)%)"
    flex_b = "1 1 0"

    # Size-critical layout lives in inline styles, not the stylesheet: WGLMakie
    # measures its pane the moment the scene initializes, and inline styles are
    # present the instant the element exists — stylesheet timing can't produce
    # a 0×0 canvas. Theme/visuals stay in SPLIT_STYLES.
    pane_style(flex) = Styles(
        "display" => "flex", "flex-direction" => "column",
        "overflow" => "hidden", "box-sizing" => "border-box",
        "min-width" => "0", "min-height" => "0", "flex" => flex,
    )
    body_style = Styles(
        "flex" => "1 1 0", "min-width" => "0", "min-height" => "0",
        "position" => "relative", "overflow" => "hidden",
    )

    function pane(content, title_idx, class, flex)
        children = Any[]
        isnothing(sc.titles) || push!(children, split_pane_header(sc.titles[title_idx], sc.collapsible))
        push!(children, DOM.div(content; class="bw-split-body", style=body_style))
        return DOM.div(children...; class="bw-split-pane $class", style=pane_style(flex))
    end
    pane_a = pane(sc.a, 1, "bw-split-a", flex_a)
    pane_b = pane(sc.b, 2, "bw-split-b", flex_b)
    gutter = DOM.div(DOM.div(class="bw-split-grip"); class="bw-split-gutter",
                     style=Styles("flex" => "0 0 var(--bw-gutter-size)"))

    drag_script = js"""
    (() => {
        const paneA = $(pane_a);
        const paneB = $(pane_b);
        const gutter = $(gutter);
        const container = gutter.closest('.bw-split');
        const minFrac = $(sc.min_fraction);
        const initSplit = $(init_split);
        const FLEX_A = $(flex_a);
        const FLEX_B = $(flex_b);
        const dirObs = $(dir_str);
        const splitObs = $(sc.split);
        const collapsedObs = $(sc.collapsed);

        const isRow = () => container.classList.contains('bw-split-row');

        let dragging = false;
        let frac = initSplit / 100;

        function setSplit(f, notify) {
            frac = Math.min(Math.max(f, minFrac), 1 - minFrac);
            container.style.setProperty('--bw-split-a', (frac * 100) + '%');
            if (notify) splitObs.notify(frac);
        }

        gutter.addEventListener('pointerdown', (e) => {
            if (collapsedObs.value !== 0) return;
            dragging = true;
            container.classList.add('bw-dragging');
            gutter.setPointerCapture(e.pointerId);
            e.preventDefault();
        });
        gutter.addEventListener('pointermove', (e) => {
            if (!dragging) return;
            const rect = container.getBoundingClientRect();
            setSplit(isRow()
                ? (e.clientX - rect.left) / rect.width
                : (e.clientY - rect.top) / rect.height, false);
        });
        const endDrag = (e) => {
            if (!dragging) return;
            dragging = false;
            container.classList.remove('bw-dragging');
            try { gutter.releasePointerCapture(e.pointerId); } catch (_) {}
            splitObs.notify(frac);
        };
        gutter.addEventListener('pointerup', endDrag);
        gutter.addEventListener('pointercancel', endDrag);
        gutter.addEventListener('dblclick', () => setSplit(initSplit / 100, true));
        splitObs.on((f) => { if (!dragging && Math.abs(f - frac) > 1e-6) setSplit(f, false); });

        // Orientation: same DOM, just flip the flex axis (and the cursor /
        // grip styling that hangs off the direction class).
        function applyDirection(d) {
            const row = d === 'row';
            container.classList.toggle('bw-split-row', row);
            container.classList.toggle('bw-split-column', !row);
            container.style.flexDirection = row ? 'row' : 'column';
        }
        dirObs.on(applyDirection);

        // Collapse: flex is set inline so it can't be left in a bad state if
        // the stylesheet is slow to apply.
        function applyCollapsed(which) {
            const panes = [paneA, paneB];
            for (let i = 0; i < 2; i++) {
                const on = which === i + 1;
                panes[i].classList.toggle('bw-collapsed', on);
                panes[i].style.flex = on ? '0 0 auto' : (i === 0 ? FLEX_A : FLEX_B);
            }
            if (which !== 0) panes[which === 1 ? 1 : 0].style.flex = '1 1 0';
            container.classList.toggle('bw-has-collapsed', which !== 0);
        }
        collapsedObs.on(applyCollapsed);
        applyCollapsed(collapsedObs.value);

        container.querySelectorAll(':scope > .bw-split-pane > .bw-split-header .bw-split-collapse').forEach((btn) => {
            btn.addEventListener('click', () => {
                const idx = btn.closest('.bw-split-pane').classList.contains('bw-split-a') ? 1 : 2;
                collapsedObs.notify(collapsedObs.value === idx ? 0 : idx);
            });
        });
    })();
    """

    dir_class = is_row ? "bw-split-row" : "bw-split-column"
    container = DOM.div(
        THEME_STYLES, SPLIT_STYLES,
        pane_a, gutter, pane_b, DOM.script(drag_script);
        class="bw-split $dir_class",
        style=Styles(sc.style,
            "display" => "flex",
            "flex-direction" => is_row ? "row" : "column",
            "width" => "100%", "height" => "100%",
            "min-width" => "0", "min-height" => "0",
            "box-sizing" => "border-box",
            "--bw-split-a" => "$(init_split)%",
        ),
    )
    return Bonito.jsrender(session, container)
end

const SPLIT_STYLES = Styles(
    CSS(".bw-split-pane", "background-color" => "var(--bw-bg-panel)"),

    # Collapsed pane: body and title hidden, chevron rotated, gutter gone.
    CSS(".bw-split.bw-has-collapsed > .bw-split-gutter", "display" => "none"),
    CSS(".bw-split-pane.bw-collapsed > .bw-split-body", "display" => "none"),
    CSS(".bw-split-pane.bw-collapsed > .bw-split-header .bw-split-chevron",
        "transform" => "rotate(-90deg)"),

    # Header bar
    CSS(".bw-split-header",
        "display" => "flex",
        "align-items" => "center",
        "justify-content" => "space-between",
        "gap" => "var(--bw-space-2)",
        "padding" => "0 var(--bw-space-2)",
        "min-height" => "calc(var(--bw-bar-size) * 0.8)",
        "flex" => "0 0 auto",
        "border-bottom" => "1px solid var(--bw-border)",
        "background-color" => "var(--bw-bg-bar)",
        "user-select" => "none",
    ),
    CSS(".bw-split-title",
        "font-family" => "var(--bw-font)",
        "font-size" => "var(--bw-font-size-sm)",
        "font-weight" => "600",
        "color" => "var(--bw-text-muted)",
        "text-transform" => "uppercase",
        "letter-spacing" => "0.06em",
        "white-space" => "nowrap",
        "overflow" => "hidden",
        "text-overflow" => "ellipsis",
    ),
    CSS(".bw-split-collapse",
        "display" => "flex",
        "align-items" => "center",
        "justify-content" => "center",
        "width" => "calc(var(--bw-bar-size) - 12px)",
        "height" => "calc(var(--bw-bar-size) - 12px)",
        "padding" => "0",
        "flex-shrink" => "0",
        "background" => "transparent",
        "border" => "none",
        "border-radius" => "var(--bw-radius-sm)",
        "color" => "var(--bw-text-muted)",
        "cursor" => "pointer",
        "transition" => "all var(--bw-transition)",
        "-webkit-tap-highlight-color" => "transparent",
    ),
    CSS(".bw-split-collapse:hover",
        "background-color" => "var(--bw-bg-hover)",
        "color" => "var(--bw-accent)",
    ),
    CSS(".bw-split-chevron",
        "display" => "flex",
        "line-height" => "0",
        "transition" => "transform var(--bw-transition)",
    ),

    # Gutter
    CSS(".bw-split-gutter",
        "display" => "flex",
        "align-items" => "center",
        "justify-content" => "center",
        "position" => "relative",
        "z-index" => "5",
        "touch-action" => "none",
        "transition" => "background-color var(--bw-transition)",
    ),
    CSS(".bw-split-row > .bw-split-gutter", "cursor" => "col-resize"),
    CSS(".bw-split-column > .bw-split-gutter", "cursor" => "row-resize"),
    CSS(".bw-split-gutter:hover", "background-color" => "var(--bw-accent-bg)"),
    CSS(".bw-split.bw-dragging > .bw-split-gutter", "background-color" => "var(--bw-accent-bg)"),

    # The grip — a thin centered handle elongated along the gutter axis.
    CSS(".bw-split-grip",
        "background-color" => "var(--bw-border)",
        "border-radius" => "2px",
        "transition" => "background-color var(--bw-transition)",
    ),
    CSS(".bw-split-row > .bw-split-gutter > .bw-split-grip", "width" => "2px", "height" => "32px"),
    CSS(".bw-split-column > .bw-split-gutter > .bw-split-grip", "width" => "32px", "height" => "2px"),
    CSS(".bw-split-gutter:hover > .bw-split-grip", "background-color" => "var(--bw-accent)"),
    CSS(".bw-split.bw-dragging > .bw-split-gutter > .bw-split-grip", "background-color" => "var(--bw-accent)"),

    # While dragging: no text selection, and panes (canvases!) must not
    # swallow pointer moves.
    CSS(".bw-split.bw-dragging", "user-select" => "none"),
    CSS(".bw-split.bw-dragging .bw-split-body", "pointer-events" => "none"),
)
