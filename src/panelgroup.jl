"""
    PanelGroup(items...; mode=:tabs, active=1, collapsible=true,
               mode_buttons=true, draggable=true, min_fraction=0.1,
               style=Styles())
    PanelGroup("Editor" => editor, "Plot" => fig, "Log" => log)

VSCode-style panel management for a set of named panels: show them as **tabs**
or **side by side** (with draggable resize gutters), switchable at runtime via
the widgets in the group bar — or by dragging a tab into a layout slot.

The bar shows one button per panel plus (right-aligned) the layout widgets:
tabs / horizontal split / vertical split toggles and a collapse chevron that
folds the whole group down to the bar.

**Tab dragging** (`draggable=true`): drag a tab over the body and drop zones
light up — left/right edges dock the panel there in a horizontal split,
top/bottom in a vertical split, center switches back to tabs with that panel
active. Dropping on another tab in the strip reorders the panels. Dragging
works with mouse and touch (drag the tab downwards into the body on touch).

All panels stay mounted across every layout change — the same DOM nodes are
re-flowed (or moved, for reorders) without re-rendering — so WebGL contexts,
Makie cameras, and widget state survive switching between tabs and splits.

Observable state (all bidirectional):

- `mode::Observable{Symbol}` — `:tabs`, `:row` (side by side), or `:column`
  (stacked). `:horizontal`/`:vertical` accepted as aliases on construction.
- `active::Observable{Int}` — the shown tab in `:tabs` mode (highlighted in
  split modes). Indices always refer to the original construction order.
- `order::Observable{Vector{Int}}` — display order as a permutation of
  original panel indices, updated by tab drags; set it from Julia to restore
  a saved arrangement.
- `collapsed::Observable{Bool}` — group folded to just its bar.
- `fractions::Observable{Vector{Float64}}` — per-*position* share of the
  split axis (sums to 1), notified after each gutter drag.

Mobile: below 700px viewport width the group always lays out as tabs (splits
are unusable on phones), the split-mode buttons hide, and drop zones reduce to
"make active"; `mode` is preserved and re-applied once the viewport is wide
again. Gutters and bar buttons grow on coarse pointers via
`--bw-bar-size`/`--bw-gutter-size`.
"""
struct PanelGroup
    labels::Vector{Any}
    contents::Vector{Any}
    mode::Observable{Symbol}
    active::Observable{Int}
    order::Observable{Vector{Int}}
    collapsed::Observable{Bool}
    fractions::Observable{Vector{Float64}}
    collapsible::Bool
    mode_buttons::Bool
    draggable::Bool
    min_fraction::Float64
    style::Styles
end

function PanelGroup(items::AbstractVector{<:Pair};
                    mode::Union{Symbol,Observable{Symbol}}=:tabs,
                    active::Integer=1,
                    collapsible::Bool=true,
                    mode_buttons::Bool=true,
                    draggable::Bool=true,
                    min_fraction::Real=0.1,
                    style=Styles())
    isempty(items) && throw(ArgumentError("PanelGroup needs at least one panel"))
    n = length(items)
    1 ≤ active ≤ n || throw(ArgumentError("active=$active out of range 1:$n"))
    norm(m::Symbol) = m === :tabs ? :tabs : normalize_direction(m)
    mode_obs = mode isa Observable ? mode : Observable(norm(mode))
    mode_obs[] = norm(mode_obs[])
    return PanelGroup(
        Any[p.first for p in items], Any[p.second for p in items],
        mode_obs, Observable(Int(active)), Observable(collect(1:n)),
        Observable(false), Observable(fill(1.0 / n, n)),
        collapsible, mode_buttons, draggable, Float64(min_fraction), style,
    )
end
PanelGroup(items::Pair...; kwargs...) = PanelGroup(collect(items); kwargs...)

function Bonito.jsrender(session::Session, g::PanelGroup)
    n = length(g.labels)
    init_mode = g.mode[]
    init_active = g.active[]
    mode_str = string_bridge(g.mode)

    tab_buttons = [
        DOM.button(DOM.span(g.labels[i]; class="bw-tab-label");
                   class=(i == init_active ? "bw-tab bw-active" : "bw-tab"))
        for i in 1:n
    ]
    tabs_strip = DOM.div(tab_buttons...; class="bw-group-tabs")

    actions = Any[]
    if g.mode_buttons
        for (m, icon, label) in (("tabs", icon_tabs(), "Show as tabs"),
                                 ("row", icon_split_row(), "Split horizontally"),
                                 ("column", icon_split_column(), "Split vertically"))
            push!(actions, DOM.button(icon;
                class=(m == string(init_mode) ? "bw-icon-btn bw-group-mode bw-active" : "bw-icon-btn bw-group-mode"),
                var"data-mode"=m, title=label))
        end
    end
    if g.collapsible
        push!(actions, DOM.button(DOM.span(icon_chevron_down(); class="bw-group-chevron");
                                  class="bw-icon-btn bw-group-collapse", title="Collapse / expand"))
    end
    bar = DOM.div(tabs_strip, DOM.div(actions...; class="bw-group-actions");
                  class="bw-group-bar")

    # Panels keep one set of DOM nodes; mode switches only rewrite inline
    # layout styles, reorders move nodes. Initial inline styles match the
    # initial mode so wrapped canvases measure real sizes at first paint.
    is_tabs = init_mode === :tabs
    function panel_style(i)
        base = [
            "display" => "flex", "flex-direction" => "column",
            "min-width" => "0", "min-height" => "0",
            "overflow" => "hidden", "box-sizing" => "border-box",
        ]
        if is_tabs
            append!(base, [
                "position" => "absolute", "inset" => "0",
                "visibility" => i == init_active ? "visible" : "hidden",
                "pointer-events" => i == init_active ? "auto" : "none",
            ])
        else
            append!(base, ["position" => "relative", "flex" => "1 1 0"])
        end
        return Styles(base...)
    end
    panels = [DOM.div(g.contents[i]; class="bw-group-panel", style=panel_style(i)) for i in 1:n]
    gutters = [DOM.div(DOM.div(class="bw-split-grip"); class="bw-group-gutter bw-split-gutter",
                       style=Styles("flex" => "0 0 var(--bw-gutter-size)",
                                    "display" => is_tabs ? "none" : "flex"))
               for _ in 1:(n - 1)]
    overlay = DOM.div(; class="bw-drop-overlay",
                      style=Styles("position" => "absolute", "display" => "none",
                                   "pointer-events" => "none", "z-index" => "100"))
    body_children = Any[panels[1]]
    for i in 2:n
        push!(body_children, gutters[i - 1], panels[i])
    end
    push!(body_children, overlay)
    body = DOM.div(body_children...;
        class="bw-group-body",
        style=Styles(
            "position" => "relative",
            "display" => "flex",
            "flex-direction" => init_mode === :column ? "column" : "row",
            "flex" => "1 1 0",
            "min-width" => "0", "min-height" => "0",
            "overflow" => "hidden",
        ),
    )

    wire = js"""
    (() => {
        const bar = $(bar);
        const body = $(body);
        const container = bar.parentElement;
        const modeObs = $(mode_str);
        const activeObs = $(g.active);
        const orderObs = $(g.order);
        const collapsedObs = $(g.collapsed);
        const fracObs = $(g.fractions);
        const minFrac = $(g.min_fraction);
        const n = $(n);
        const draggable = $(g.draggable);

        const tabsStrip = bar.querySelector('.bw-group-tabs');
        const tabs = Array.from(tabsStrip.querySelectorAll('.bw-tab'));
        const modeBtns = Array.from(bar.querySelectorAll('.bw-group-mode'));
        const collapseBtn = bar.querySelector('.bw-group-collapse');
        const panels = Array.from(body.querySelectorAll(':scope > .bw-group-panel'));
        const gutters = Array.from(body.querySelectorAll(':scope > .bw-group-gutter'));
        const overlay = body.querySelector(':scope > .bw-drop-overlay');

        let fractions = fracObs.value.slice();   // indexed by display position
        let order = orderObs.value.slice();      // display position -> original id
        let suppressClick = false;
        // Below 700px splits are unusable — force tab layout, keep `mode`.
        const narrow = window.matchMedia('(max-width: 700px)');

        function effectiveMode() {
            return narrow.matches ? 'tabs' : modeObs.value;
        }

        // Reorders are real DOM moves (appendChild re-parents in sequence);
        // canvases keep their WebGL contexts through this.
        function applyOrder() {
            for (let pos = 0; pos < n; pos++) {
                body.appendChild(panels[order[pos] - 1]);
                if (pos < n - 1) body.appendChild(gutters[pos]);
            }
            body.appendChild(overlay);
            order.forEach(id => tabsStrip.appendChild(tabs[id - 1]));
        }

        function applyLayout() {
            const mode = effectiveMode();
            const isTabs = mode === 'tabs';
            container.dataset.mode = mode;
            body.style.flexDirection = mode === 'column' ? 'column' : 'row';
            const active = activeObs.value;
            order.forEach((id, pos) => {
                const p = panels[id - 1];
                if (isTabs) {
                    const on = id === active;
                    p.style.position = 'absolute';
                    p.style.inset = '0';
                    p.style.flex = '';
                    p.style.visibility = on ? 'visible' : 'hidden';
                    p.style.pointerEvents = on ? 'auto' : 'none';
                } else {
                    p.style.position = 'relative';
                    p.style.inset = '';
                    p.style.flex = fractions[pos] + ' 1 0%';
                    p.style.visibility = 'visible';
                    p.style.pointerEvents = 'auto';
                }
            });
            gutters.forEach(gt => { gt.style.display = isTabs ? 'none' : 'flex'; });
            tabs.forEach((t, i) => t.classList.toggle('bw-active', (i + 1) === active));
            modeBtns.forEach(b => b.classList.toggle('bw-active', b.dataset.mode === modeObs.value));
        }

        function applyCollapsed(c) {
            container.classList.toggle('bw-collapsed', c);
            body.style.display = c ? 'none' : 'flex';
        }

        tabs.forEach((t, i) => t.addEventListener('click', () => {
            if (suppressClick) { suppressClick = false; return; }
            activeObs.notify(i + 1);
        }));
        modeBtns.forEach(b => b.addEventListener('click', () => modeObs.notify(b.dataset.mode)));
        if (collapseBtn) collapseBtn.addEventListener('click', () =>
            collapsedObs.notify(!container.classList.contains('bw-collapsed')));

        modeObs.on(applyLayout);
        activeObs.on(applyLayout);
        collapsedObs.on(applyCollapsed);
        fracObs.on((f) => { fractions = f.slice(); applyLayout(); });
        orderObs.on((o) => { order = o.slice(); applyOrder(); applyLayout(); });
        const onNarrow = () => applyLayout();
        if (narrow.addEventListener) narrow.addEventListener('change', onNarrow);
        else narrow.addListener(onNarrow);

        // Gutter drag: redistribute space between the two panels adjacent in
        // *display order* (like VSCode). Fractions notify Julia on release.
        gutters.forEach((gutter, i) => {
            let dragging = false;
            let combinedStart = 0, combinedSize = 0, total = 0;
            let pa = null, pb = null;
            const isRow = () => effectiveMode() === 'row';
            gutter.addEventListener('pointerdown', (e) => {
                pa = panels[order[i] - 1];
                pb = panels[order[i + 1] - 1];
                const ra = pa.getBoundingClientRect();
                const rb = pb.getBoundingClientRect();
                if (isRow()) {
                    combinedStart = ra.left;
                    combinedSize = rb.right - ra.left;
                } else {
                    combinedStart = ra.top;
                    combinedSize = rb.bottom - ra.top;
                }
                total = fractions[i] + fractions[i + 1];
                dragging = true;
                container.classList.add('bw-dragging');
                gutter.setPointerCapture(e.pointerId);
                e.preventDefault();
            });
            gutter.addEventListener('pointermove', (e) => {
                if (!dragging) return;
                const pos = isRow() ? e.clientX : e.clientY;
                let fa = (pos - combinedStart) / combinedSize * total;
                fa = Math.min(Math.max(fa, minFrac), total - minFrac);
                fractions[i] = fa;
                fractions[i + 1] = total - fa;
                pa.style.flex = fractions[i] + ' 1 0%';
                pb.style.flex = fractions[i + 1] + ' 1 0%';
            });
            const endDrag = (e) => {
                if (!dragging) return;
                dragging = false;
                container.classList.remove('bw-dragging');
                try { gutter.releasePointerCapture(e.pointerId); } catch (_) {}
                fracObs.notify(fractions.slice());
            };
            gutter.addEventListener('pointerup', endDrag);
            gutter.addEventListener('pointercancel', endDrag);
            gutter.addEventListener('dblclick', () => {
                fractions = fractions.map(() => 1 / n);
                fracObs.notify(fractions.slice());
            });
        });

        // Tab dragging: drop on a body zone to dock (left/right → row,
        // top/bottom → column, center → tabs + active), or on another tab to
        // reorder. Notifies go through the observables; their .on handlers do
        // the actual re-apply, so Julia-initiated updates take the same path.
        if (draggable && n > 1) {
            const zoneAt = (e) => {
                if (collapsedObs.value) return null;
                const r = body.getBoundingClientRect();
                if (r.width === 0 || e.clientX < r.left || e.clientX > r.right ||
                    e.clientY < r.top || e.clientY > r.bottom) return null;
                if (narrow.matches) return 'center';
                const fx = (e.clientX - r.left) / r.width;
                const fy = (e.clientY - r.top) / r.height;
                if (fx < 0.2) return 'left';
                if (fx > 0.8) return 'right';
                if (fy < 0.25) return 'top';
                if (fy > 0.75) return 'bottom';
                return 'center';
            };
            const showOverlay = (zone) => {
                if (!zone) { overlay.style.display = 'none'; return; }
                const o = { left: '0%', top: '0%', width: '100%', height: '100%' };
                if (zone === 'left') o.width = '50%';
                if (zone === 'right') { o.width = '50%'; o.left = '50%'; }
                if (zone === 'top') o.height = '50%';
                if (zone === 'bottom') { o.height = '50%'; o.top = '50%'; }
                overlay.style.display = 'block';
                overlay.style.left = o.left;
                overlay.style.top = o.top;
                overlay.style.width = o.width;
                overlay.style.height = o.height;
            };
            const clearStripMarks = () => tabs.forEach(t =>
                t.classList.remove('bw-drop-before', 'bw-drop-after'));
            const stripAt = (e) => {
                const r = tabsStrip.getBoundingClientRect();
                if (e.clientX < r.left || e.clientX > r.right ||
                    e.clientY < r.top || e.clientY > r.bottom) return null;
                for (const t of tabs) {
                    const tr = t.getBoundingClientRect();
                    if (e.clientX >= tr.left && e.clientX <= tr.right) {
                        return { btn: t, before: e.clientX < (tr.left + tr.right) / 2 };
                    }
                }
                return null;
            };

            tabs.forEach((btn, idx) => {
                const id = idx + 1;
                btn.addEventListener('pointerdown', (e) => {
                    if (e.button !== undefined && e.button !== 0) return;
                    const startX = e.clientX, startY = e.clientY;
                    let engaged = false;
                    let ghost = null;
                    let stripTarget = null;
                    const onMove = (e2) => {
                        if (!engaged) {
                            if (Math.hypot(e2.clientX - startX, e2.clientY - startY) < 6) return;
                            engaged = true;
                            btn.classList.add('bw-drag-src');
                            ghost = document.createElement('div');
                            ghost.className = 'bw-drag-ghost';
                            ghost.textContent = btn.textContent;
                            document.body.appendChild(ghost);
                        }
                        ghost.style.left = (e2.clientX + 10) + 'px';
                        ghost.style.top = (e2.clientY + 14) + 'px';
                        clearStripMarks();
                        const st = stripAt(e2);
                        if (st && st.btn !== btn) {
                            stripTarget = st;
                            st.btn.classList.add(st.before ? 'bw-drop-before' : 'bw-drop-after');
                            showOverlay(null);
                        } else {
                            stripTarget = null;
                            showOverlay(zoneAt(e2));
                        }
                    };
                    const finish = (apply, e2) => {
                        window.removeEventListener('pointermove', onMove);
                        window.removeEventListener('pointerup', onUp);
                        window.removeEventListener('pointercancel', onCancel);
                        if (!engaged) return;
                        suppressClick = true;
                        btn.classList.remove('bw-drag-src');
                        if (ghost) ghost.remove();
                        overlay.style.display = 'none';
                        const st = stripTarget;
                        clearStripMarks();
                        if (!apply) return;
                        if (st) {
                            const targetId = tabs.indexOf(st.btn) + 1;
                            const o = order.filter(x => x !== id);
                            o.splice(o.indexOf(targetId) + (st.before ? 0 : 1), 0, id);
                            orderObs.notify(o);
                        } else {
                            const zone = zoneAt(e2);
                            if (!zone) return;
                            if (zone === 'center') {
                                activeObs.notify(id);
                                if (modeObs.value !== 'tabs') modeObs.notify('tabs');
                            } else {
                                const o = order.filter(x => x !== id);
                                (zone === 'left' || zone === 'top') ? o.unshift(id) : o.push(id);
                                orderObs.notify(o);
                                activeObs.notify(id);
                                const m = (zone === 'left' || zone === 'right') ? 'row' : 'column';
                                if (modeObs.value !== m) modeObs.notify(m);
                            }
                        }
                    };
                    const onUp = (e2) => finish(true, e2);
                    const onCancel = (e2) => finish(false, e2);
                    window.addEventListener('pointermove', onMove);
                    window.addEventListener('pointerup', onUp);
                    window.addEventListener('pointercancel', onCancel);
                });
            });
        }

        applyOrder();
        applyLayout();
        applyCollapsed(collapsedObs.value);
    })();
    """

    container = DOM.div(
        THEME_STYLES, ICON_BUTTON_STYLES, TABS_STYLES, SPLIT_STYLES, PANEL_GROUP_STYLES,
        bar, body, DOM.script(wire);
        class="bw-group",
        var"data-mode"=string(init_mode),
        style=Styles(g.style,
            "display" => "flex",
            "flex-direction" => "column",
            "width" => "100%", "height" => "100%",
            "min-width" => "0", "min-height" => "0",
            "box-sizing" => "border-box",
        ),
    )
    return Bonito.jsrender(session, container)
end

const PANEL_GROUP_STYLES = Styles(
    CSS(".bw-group-bar",
        "display" => "flex",
        "align-items" => "stretch",
        "justify-content" => "space-between",
        "gap" => "var(--bw-space-2)",
        "flex" => "0 0 auto",
        "min-height" => "var(--bw-bar-size)",
        "background-color" => "var(--bw-bg-bar)",
        "border-bottom" => "1px solid var(--bw-border)",
    ),
    CSS(".bw-group.bw-collapsed > .bw-group-bar", "border-bottom" => "none"),
    CSS(".bw-group-tabs",
        "display" => "flex",
        "min-width" => "0",
        "overflow-x" => "auto",
        "overflow-y" => "hidden",
        "scrollbar-width" => "none",
        "-webkit-overflow-scrolling" => "touch",
    ),
    CSS(".bw-group-tabs::-webkit-scrollbar", "display" => "none"),
    # pan-x keeps horizontal bar scrolling native on touch while vertical
    # pointer moves (dragging a tab down into the body) still reach JS.
    CSS(".bw-group-tabs > .bw-tab", "touch-action" => "pan-x"),
    CSS(".bw-group-actions",
        "display" => "flex",
        "align-items" => "center",
        "gap" => "var(--bw-space-1)",
        "padding" => "0 var(--bw-space-2)",
        "flex" => "0 0 auto",
    ),
    CSS(".bw-group-chevron",
        "display" => "flex",
        "line-height" => "0",
        "transition" => "transform var(--bw-transition)",
    ),
    CSS(".bw-group.bw-collapsed .bw-group-chevron", "transform" => "rotate(-90deg)"),
    CSS(".bw-group-panel", "background-color" => "var(--bw-bg-panel)"),
    # In split modes the tab strip only highlights; keep the active underline
    # subtler than in tabs mode.
    CSS(".bw-group:not([data-mode='tabs']) .bw-tab.bw-active",
        "box-shadow" => "inset 0 -2px 0 var(--bw-border)"),
    # No split-mode buttons on narrow screens (layout is forced to tabs).
    CSS("@media (max-width: 700px)",
        CSS(".bw-group-mode[data-mode='row']", "display" => "none"),
        CSS(".bw-group-mode[data-mode='column']", "display" => "none"),
    ),
    CSS(".bw-group.bw-dragging", "user-select" => "none"),
    CSS(".bw-group.bw-dragging .bw-group-panel", "pointer-events" => "none"),

    # Tab dragging chrome -----------------------------------------------------
    CSS(".bw-drag-ghost",
        "position" => "fixed",
        "z-index" => "calc(var(--bw-z-float) + 1)",
        "padding" => "var(--bw-space-1) var(--bw-space-3)",
        "background-color" => "var(--bw-bg-panel)",
        "color" => "var(--bw-text)",
        "font-family" => "var(--bw-font)",
        "font-size" => "var(--bw-font-size-sm)",
        "border" => "1px solid var(--bw-accent)",
        "border-radius" => "var(--bw-radius-sm)",
        "box-shadow" => "var(--bw-shadow)",
        "opacity" => "0.9",
        "pointer-events" => "none",
        "white-space" => "nowrap",
    ),
    CSS(".bw-tab.bw-drag-src", "opacity" => "0.4"),
    CSS(".bw-tab.bw-drop-before", "box-shadow" => "inset 2px 0 0 var(--bw-accent)"),
    CSS(".bw-tab.bw-drop-after", "box-shadow" => "inset -2px 0 0 var(--bw-accent)"),
    CSS(".bw-drop-overlay",
        "background-color" => "var(--bw-accent-bg)",
        "border" => "2px solid var(--bw-accent)",
        "box-sizing" => "border-box",
        "transition" => "all 0.08s ease",
    ),
)
