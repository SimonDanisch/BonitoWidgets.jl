"""
    Workspace(items...; layout=nothing, style=Styles())
    Workspace("Editor" => ed, "Plot" => fig, "Log" => log)

Full VSCode-style pane/tab management: a **split tree whose leaves are tab
groups**. Dragging a tab to the edge of a group splits that group — the
dragged panel forms a new group beside it while the remaining tabs stay
together (`| tabs(Editor, Plot) | Log |`). Dragging onto another group's tab
strip (or its center zone) moves the panel into that group; a group dissolves
when its last tab leaves. Gutters between groups drag-resize.

Panel contents are rendered once and *moved* between groups (never
re-rendered), so WebGL contexts, Makie cameras, and widget state survive every
rearrangement.

`layout::Observable{Dict{String,Any}}` holds the tree as plain JSON-able data
— bidirectional: every user drag notifies it (persist it to disk if you
like), and setting it from Julia rebuilds the arrangement. Panels are
referenced by their 1-based construction index. Build trees with the helpers:

```julia
ws = Workspace("Editor" => ed, "Plot" => fig, "Log" => log;
               layout=hsplit(tabgroup(1, 2), tabgroup(3); fractions=[0.7, 0.3]))
on(ws.layout) do tree
    # save tree (plain Dict/Vector data) ...
end
```

- `tabgroup(panels...; active=first)` — a leaf showing those panels as tabs.
- `hsplit(children...; fractions)` / `vsplit(children...; fractions)` —
  split nodes (children are leaves or further splits).

The default layout is a single tab group with all panels.

Mobile: below 700px viewport width the whole tree is *displayed* as a single
tab group (the layout state is untouched and comes back when the viewport
widens); tab dragging is disabled there, clicking switches.
"""
struct Workspace
    labels::Vector{String}
    contents::Vector{Any}
    layout::Observable{Dict{String,Any}}
    min_fraction::Float64
    style::Styles
end

"""
    tabgroup(panels::Integer...; active=first(panels))

A [`Workspace`](@ref) layout leaf: the given panel indices shown as tabs.
"""
function tabgroup(panels::Integer...; active::Integer=first(panels))
    active in panels || throw(ArgumentError("active=$active is not one of the panels"))
    return Dict{String,Any}("type" => "tabs", "panels" => collect(Int, panels), "active" => Int(active))
end

function splitnode(type::String, children; fractions)
    length(children) ≥ 2 || throw(ArgumentError("a split needs at least two children"))
    length(fractions) == length(children) ||
        throw(ArgumentError("fractions must match the number of children"))
    return Dict{String,Any}(
        "type" => type,
        "children" => Any[children...],
        "fractions" => collect(Float64, fractions),
    )
end

"""
    hsplit(children...; fractions=equal)

A [`Workspace`](@ref) layout node placing `children` side by side
(left → right). Children are [`tabgroup`](@ref)s or nested splits.
"""
hsplit(children...; fractions=fill(1.0 / length(children), length(children))) =
    splitnode("row", children; fractions)

"""
    vsplit(children...; fractions=equal)

A [`Workspace`](@ref) layout node stacking `children` (top → bottom).
"""
vsplit(children...; fractions=fill(1.0 / length(children), length(children))) =
    splitnode("column", children; fractions)

function Workspace(items::AbstractVector{<:Pair};
                   layout::Union{Nothing,Dict{String,Any},Observable{Dict{String,Any}}}=nothing,
                   min_fraction::Real=0.1,
                   style=Styles())
    isempty(items) && throw(ArgumentError("Workspace needs at least one panel"))
    n = length(items)
    init = isnothing(layout) ? tabgroup(1:n...) : layout
    layout_obs = init isa Observable ? init : Observable(init)
    return Workspace(
        String[String(p.first) for p in items], Any[p.second for p in items],
        layout_obs, Float64(min_fraction), style,
    )
end
Workspace(items::Pair...; kwargs...) = Workspace(collect(items); kwargs...)

function Bonito.jsrender(session::Session, ws::Workspace)
    n = length(ws.labels)

    # Panel contents render once, parked stacked at full workspace size so
    # canvases measure real dimensions before the dock chrome (JS-built)
    # takes over. After the first render() the parking is hidden and panels
    # live inside leaf bodies.
    panel_els = [
        DOM.div(ws.contents[i];
                class="bw-ws-panel",
                style=Styles(
                    "position" => "absolute", "inset" => "0",
                    "display" => "flex", "flex-direction" => "column",
                    "min-width" => "0", "min-height" => "0",
                    "overflow" => "hidden", "box-sizing" => "border-box",
                    "visibility" => i == 1 ? "visible" : "hidden",
                ))
        for i in 1:n
    ]
    parking = DOM.div(panel_els...;
        class="bw-ws-parking",
        style=Styles("flex" => "1 1 0", "position" => "relative",
                     "min-width" => "0", "min-height" => "0"))
    chrome = DOM.div(;
        class="bw-ws-chrome",
        style=Styles("flex" => "1 1 0", "display" => "none",
                     "min-width" => "0", "min-height" => "0"))

    wire = js"""
    (() => {
        const chrome = $(chrome);
        const parking = $(parking);
        const layoutObs = $(ws.layout);
        const labels = $(ws.labels);
        const minFrac = $(ws.min_fraction);
        const n = $(n);
        const panelEls = Array.from(parking.querySelectorAll(':scope > .bw-ws-panel'));

        const clone = (x) => JSON.parse(JSON.stringify(x));
        let tree = clone(layoutObs.value);
        const narrow = window.matchMedia('(max-width: 700px)');

        // ---- tree helpers ---------------------------------------------------
        const isLeaf = (node) => node.type === 'tabs';

        function leafOf(node, id) {
            if (isLeaf(node)) return node.panels.includes(id) ? node : null;
            for (const c of node.children) {
                const f = leafOf(c, id);
                if (f) return f;
            }
            return null;
        }

        // Drop empty leaves, collapse single-child splits, renormalize fractions.
        function normalize(node) {
            if (isLeaf(node)) return node.panels.length ? node : null;
            const kids = [], fracs = [];
            node.children.forEach((c, i) => {
                const k = normalize(c);
                if (k) { kids.push(k); fracs.push(node.fractions[i] || 1); }
            });
            if (kids.length === 0) return null;
            if (kids.length === 1) return kids[0];
            const s = fracs.reduce((a, b) => a + b, 0);
            node.children = kids;
            node.fractions = fracs.map(f => f / s);
            return node;
        }

        // Replace `target` (by object identity) with `repl` anywhere in the tree.
        function replaceNode(node, target, repl) {
            if (node === target) return repl;
            if (!isLeaf(node)) node.children = node.children.map(c => replaceNode(c, target, repl));
            return node;
        }

        function allPanels(node, out = []) {
            if (isLeaf(node)) out.push(...node.panels);
            else node.children.forEach(c => allPanels(c, out));
            return out;
        }

        // ---- rendering ------------------------------------------------------
        let suppressClick = false;

        function buildLeaf(leaf) {
            const group = document.createElement('div');
            group.className = 'bw-ws-group';
            const bar = document.createElement('div');
            bar.className = 'bw-group-bar';
            const strip = document.createElement('div');
            strip.className = 'bw-group-tabs';
            bar.appendChild(strip);
            const body = document.createElement('div');
            body.className = 'bw-ws-body';
            group.appendChild(bar);
            group.appendChild(body);
            group._node = leaf;
            group._strip = strip;
            group._body = body;

            leaf.panels.forEach((id) => {
                const btn = document.createElement('button');
                btn.className = id === leaf.active ? 'bw-tab bw-active' : 'bw-tab';
                btn.textContent = labels[id - 1];
                btn._panelId = id;
                btn.addEventListener('click', () => {
                    if (suppressClick) { suppressClick = false; return; }
                    leaf.active = id;
                    notifyLayout();
                });
                if (!narrow.matches) btn.addEventListener('pointerdown', (e) => startDrag(e, id, btn));
                strip.appendChild(btn);

                const p = panelEls[id - 1];
                body.appendChild(p);
                const on = id === leaf.active;
                p.style.visibility = on ? 'visible' : 'hidden';
                p.style.pointerEvents = on ? 'auto' : 'none';
            });
            return group;
        }

        function buildSplit(node) {
            const el = document.createElement('div');
            el.className = 'bw-ws-split';
            el.style.display = 'flex';
            el.style.flexDirection = node.type === 'row' ? 'row' : 'column';
            el.style.minWidth = '0';
            el.style.minHeight = '0';
            node.children.forEach((child, i) => {
                const cel = buildNode(child);
                cel.style.flex = node.fractions[i] + ' 1 0%';
                el.appendChild(cel);
                if (i < node.children.length - 1) el.appendChild(buildGutter(node, i, el));
            });
            return el;
        }

        function buildGutter(node, i, splitEl) {
            const gutter = document.createElement('div');
            gutter.className = 'bw-group-gutter bw-split-gutter';
            gutter.style.flex = '0 0 var(--bw-gutter-size)';
            gutter.style.display = 'flex';
            const grip = document.createElement('div');
            grip.className = 'bw-split-grip';
            gutter.appendChild(grip);
            gutter.style.cursor = node.type === 'row' ? 'col-resize' : 'row-resize';

            let dragging = false;
            let combinedStart = 0, combinedSize = 0, total = 0;
            let elA = null, elB = null;
            gutter.addEventListener('pointerdown', (e) => {
                // Children are at positions 2i (gutters at odd positions).
                elA = splitEl.children[2 * i];
                elB = splitEl.children[2 * i + 2];
                const ra = elA.getBoundingClientRect();
                const rb = elB.getBoundingClientRect();
                if (node.type === 'row') {
                    combinedStart = ra.left;
                    combinedSize = rb.right - ra.left;
                } else {
                    combinedStart = ra.top;
                    combinedSize = rb.bottom - ra.top;
                }
                total = node.fractions[i] + node.fractions[i + 1];
                dragging = true;
                chrome.classList.add('bw-dragging');
                gutter.setPointerCapture(e.pointerId);
                e.preventDefault();
            });
            gutter.addEventListener('pointermove', (e) => {
                if (!dragging) return;
                const pos = node.type === 'row' ? e.clientX : e.clientY;
                let fa = (pos - combinedStart) / combinedSize * total;
                fa = Math.min(Math.max(fa, minFrac), total - minFrac);
                node.fractions[i] = fa;
                node.fractions[i + 1] = total - fa;
                elA.style.flex = fa + ' 1 0%';
                elB.style.flex = (total - fa) + ' 1 0%';
            });
            const endDrag = (e) => {
                if (!dragging) return;
                dragging = false;
                chrome.classList.remove('bw-dragging');
                try { gutter.releasePointerCapture(e.pointerId); } catch (_) {}
                notifyLayout();
            };
            gutter.addEventListener('pointerup', endDrag);
            gutter.addEventListener('pointercancel', endDrag);
            return gutter;
        }

        const buildNode = (node) => isLeaf(node) ? buildLeaf(node) : buildSplit(node);

        function render() {
            // Park panels first so wiping the chrome never detaches them
            // implicitly (re-parenting preserves canvas/WebGL state).
            panelEls.forEach(p => parking.appendChild(p));
            const view = narrow.matches
                ? { type: 'tabs', panels: allPanels(tree), active: firstActive() }
                : tree;
            chrome.replaceChildren(buildNode(view));
            chrome.style.display = 'flex';
            const root = chrome.firstElementChild;
            root.style.flex = '1 1 0';
            parking.style.display = 'none';
        }

        function firstActive() {
            let node = tree;
            while (!isLeaf(node)) node = node.children[0];
            return node.active;
        }

        function notifyLayout() {
            layoutObs.notify(clone(tree));   // .on handler re-renders
        }

        layoutObs.on((v) => { tree = clone(v); render(); });
        const onNarrow = () => render();
        if (narrow.addEventListener) narrow.addEventListener('change', onNarrow);
        else narrow.addListener(onNarrow);

        // ---- tab dragging ---------------------------------------------------
        // One fixed-position overlay highlights the prospective drop region.
        const overlay = document.createElement('div');
        overlay.className = 'bw-drop-overlay';
        overlay.style.position = 'fixed';
        overlay.style.display = 'none';
        overlay.style.pointerEvents = 'none';
        overlay.style.zIndex = 'calc(var(--bw-z-float) + 1)';
        document.body.appendChild(overlay);
        let markedBtn = null;
        const clearMark = () => {
            if (markedBtn) markedBtn.classList.remove('bw-drop-before', 'bw-drop-after');
            markedBtn = null;
        };

        // Returns {leaf, kind, …} or null. kind: 'strip' (insert at index),
        // 'center', or an edge side ('left'/'right'/'top'/'bottom').
        function dropActionAt(e) {
            for (const group of chrome.querySelectorAll('.bw-ws-group')) {
                const sr = group._strip.getBoundingClientRect();
                const barR = group.firstElementChild.getBoundingClientRect();
                if (e.clientY >= barR.top && e.clientY <= barR.bottom &&
                    e.clientX >= barR.left && e.clientX <= barR.right) {
                    for (const btn of group._strip.children) {
                        const tr = btn.getBoundingClientRect();
                        if (e.clientX >= tr.left && e.clientX <= tr.right) {
                            const before = e.clientX < (tr.left + tr.right) / 2;
                            return { leaf: group._node, kind: 'strip', btn, before };
                        }
                    }
                    return { leaf: group._node, kind: 'strip', btn: null, before: false };
                }
                const r = group._body.getBoundingClientRect();
                if (e.clientX < r.left || e.clientX > r.right ||
                    e.clientY < r.top || e.clientY > r.bottom) continue;
                const fx = (e.clientX - r.left) / r.width;
                const fy = (e.clientY - r.top) / r.height;
                let kind = 'center';
                if (fx < 0.2) kind = 'left';
                else if (fx > 0.8) kind = 'right';
                else if (fy < 0.25) kind = 'top';
                else if (fy > 0.75) kind = 'bottom';
                return { leaf: group._node, kind, rect: r };
            }
            return null;
        }

        function showAction(action) {
            clearMark();
            if (!action || action.kind === 'strip') {
                overlay.style.display = 'none';
                if (action && action.btn) {
                    markedBtn = action.btn;
                    markedBtn.classList.add(action.before ? 'bw-drop-before' : 'bw-drop-after');
                }
                return;
            }
            const r = action.rect;
            let { left, top, width, height } = r;
            if (action.kind === 'left') width /= 2;
            if (action.kind === 'right') { width /= 2; left += width; }
            if (action.kind === 'top') height /= 2;
            if (action.kind === 'bottom') { height /= 2; top += height; }
            overlay.style.display = 'block';
            overlay.style.left = left + 'px';
            overlay.style.top = top + 'px';
            overlay.style.width = width + 'px';
            overlay.style.height = height + 'px';
        }

        function applyDrop(id, action) {
            const src = leafOf(tree, id);
            // No-op drops: onto the panel's own single-tab group.
            if (action.leaf === src && src.panels.length === 1 &&
                (action.kind === 'center' || action.kind === 'strip')) return;

            src.panels = src.panels.filter(p => p !== id);
            if (src.active === id) src.active = src.panels[0] ?? 0;

            if (action.kind === 'center') {
                action.leaf.panels.push(id);
                action.leaf.active = id;
            } else if (action.kind === 'strip') {
                let pos = action.leaf.panels.length;
                if (action.btn) {
                    pos = action.leaf.panels.indexOf(action.btn._panelId);
                    if (pos < 0) pos = action.leaf.panels.length;
                    else if (!action.before) pos += 1;
                }
                action.leaf.panels.splice(pos, 0, id);
                action.leaf.active = id;
            } else {
                const newLeaf = { type: 'tabs', panels: [id], active: id };
                const dir = (action.kind === 'left' || action.kind === 'right') ? 'row' : 'column';
                const before = (action.kind === 'left' || action.kind === 'top');
                const split = {
                    type: dir,
                    children: before ? [newLeaf, action.leaf] : [action.leaf, newLeaf],
                    fractions: [0.5, 0.5],
                };
                tree = replaceNode(tree, action.leaf, split);
            }
            tree = normalize(tree) || { type: 'tabs', panels: [id], active: id };
            notifyLayout();
        }

        function startDrag(e, id, btn) {
            if (e.button !== undefined && e.button !== 0) return;
            const startX = e.clientX, startY = e.clientY;
            let engaged = false;
            let ghost = null;
            let action = null;
            const onMove = (e2) => {
                if (!engaged) {
                    if (Math.hypot(e2.clientX - startX, e2.clientY - startY) < 6) return;
                    engaged = true;
                    btn.classList.add('bw-drag-src');
                    ghost = document.createElement('div');
                    ghost.className = 'bw-drag-ghost';
                    ghost.textContent = labels[id - 1];
                    document.body.appendChild(ghost);
                }
                ghost.style.left = (e2.clientX + 10) + 'px';
                ghost.style.top = (e2.clientY + 14) + 'px';
                action = dropActionAt(e2);
                showAction(action);
            };
            const finish = (apply) => {
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
                window.removeEventListener('pointercancel', onCancel);
                if (!engaged) return;
                suppressClick = true;
                btn.classList.remove('bw-drag-src');
                if (ghost) ghost.remove();
                overlay.style.display = 'none';
                clearMark();
                if (apply && action) applyDrop(id, action);
            };
            const onUp = () => finish(true);
            const onCancel = () => finish(false);
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
            window.addEventListener('pointercancel', onCancel);
        }

        render();
    })();
    """

    container = DOM.div(
        THEME_STYLES, TABS_STYLES, SPLIT_STYLES, PANEL_GROUP_STYLES, WORKSPACE_STYLES,
        chrome, parking, DOM.script(wire);
        class="bw-ws",
        style=Styles(ws.style,
            "display" => "flex",
            "flex-direction" => "column",
            "width" => "100%", "height" => "100%",
            "min-width" => "0", "min-height" => "0",
            "box-sizing" => "border-box",
        ),
    )
    return Bonito.jsrender(session, container)
end

const WORKSPACE_STYLES = Styles(
    CSS(".bw-ws-chrome > *", "min-width" => "0", "min-height" => "0"),
    CSS(".bw-ws-group",
        "display" => "flex",
        "flex-direction" => "column",
        "min-width" => "0",
        "min-height" => "0",
        "overflow" => "hidden",
    ),
    CSS(".bw-ws-body",
        "flex" => "1 1 0",
        "position" => "relative",
        "min-width" => "0",
        "min-height" => "0",
        "overflow" => "hidden",
        "background-color" => "var(--bw-bg-panel)",
    ),
    CSS(".bw-ws .bw-group-tabs > .bw-tab", "touch-action" => "pan-x"),
    CSS(".bw-ws-chrome.bw-dragging", "user-select" => "none"),
    CSS(".bw-ws-chrome.bw-dragging .bw-ws-body", "pointer-events" => "none"),
)
