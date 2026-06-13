# ── Panel ────────────────────────────────────────────────────────────────────
"""
    Panel(id, content; label=id, closable=false)

A workspace member: stable string `id`, a `label` (String or
`Observable{String}` for live-updating titles), the `content` (rendered once),
and whether it shows a close button. Pass `Panel`s to [`Workspace`](@ref), or
use the `id => content` shorthand for label==id, non-closable panels.
"""
struct Panel
    id::String
    label::Observable{String}
    content::Any
    closable::Bool
end

function Panel(id::AbstractString, content;
              label::Union{AbstractString,Observable}=id, closable::Bool=false)
    lab = label isa Observable ? label : Observable{String}(String(label))
    return Panel(String(id), lab, content, closable)
end

topanel(p::Panel) = p
topanel(p::Pair) = Panel(String(p.first), p.second)

# One stable wrapper per panel; the KeyedList ships it once (keyed by id) and
# the workspace JS *moves* the node between leaf bodies and floats.
struct PanelView
    panel::Panel
end

function Bonito.jsrender(session::Session, pv::PanelView)
    node = DOM.div(pv.panel.content;
        class="bw-ws-panel", dataPanelId=pv.panel.id,
        style=Styles(
            "position" => "absolute", "inset" => "0",
            "display" => "flex", "flex-direction" => "column",
            "min-width" => "0", "min-height" => "0",
            "overflow" => "hidden", "box-sizing" => "border-box",
            "visibility" => "hidden",
        ))
    return Bonito.jsrender(session, node)
end

"""
    Workspace(items...; layout=nothing, style=Styles())
    Workspace("Editor" => ed, "Plot" => fig, "Log" => log)
    Workspace([Panel("editor", ed; label="Editor", closable=true), ...])

Full VSCode-style pane/tab/float management. The docked area is a **split tree
whose leaves are tab groups**; on top of it float free windows. Every panel can
be a tab, a split pane, OR a floating window, and can move freely between those
states:

- Dragging a tab to the **edge** of a group splits that group — the dragged
  panel forms a new group beside it while the remaining tabs stay together
  (`| tabs(Editor, Plot) | Log |`).
- Dragging a tab onto another group's tab strip (or its center) **moves** the
  panel into that group; a group dissolves when its last tab leaves.
- Dragging a tab **out of the docked area** (past the chrome) tears it off into
  a **floating window**. Dragging a floating window's title bar back over a
  group **docks** it again (as a tab or, at an edge, a split).
- Gutters between groups drag-resize; floating windows drag-move and
  corner-resize.

Panel contents are rendered **once** and *moved* between groups and floats
(never re-rendered), so WebGL contexts, Makie cameras, Monaco editors, and
widget state survive every rearrangement.

# Dynamic membership

Panels can be added and removed at runtime — `add_panel!`, `remove_panel!`,
`float_panel!`, `dock_panel!`. Panels are identified by a **string id** (stable
across rearrangements, used in the persisted layout). The set of live panels
lives in `ws.panels::Observable{Vector{Panel}}`; their content rides a
`KeyedList`, so adding/removing never re-renders the survivors.

# Layout state

`ws.layout::Observable{Dict{String,Any}}` holds the arrangement as plain
JSON-able data — bidirectional: every user gesture notifies it (persist it to
disk if you like), and setting it from Julia rebuilds the arrangement. Its shape:

```julia
Dict(
  "root"     => <node>,          # the docked split-tree
  "floating" => [<float>, ...],  # zero or more floating windows
)
```

- `<node>` is either a tab group `Dict("type"=>"tabs", "panels"=>[ids...], "active"=>id)`
  or a split `Dict("type"=>"row"|"column", "children"=>[<node>...], "fractions"=>[...])`.
- `<float>` is `Dict("panel"=>id, "x"=>, "y"=>, "width"=>, "height"=>)`.

Build trees with the helpers:

- `tabgroup(ids...; active=first)` — a leaf showing those panels as tabs.
- `hsplit(children...; fractions)` / `vsplit(children...; fractions)` — split nodes.
- `floatpanel(id; x, y, width, height)` — a floating entry.
- `workspacelayout(root; floating=[])` — assemble the two.

```julia
ws = Workspace("Editor" => ed, "Plot" => fig, "Log" => log;
               layout=workspacelayout(hsplit(tabgroup("Editor", "Plot"), tabgroup("Log");
                                              fractions=[0.7, 0.3])))
on(ws.layout) do tree
    # save tree (plain Dict/Vector data) ...
end
```

The default layout is a single tab group with all panels.

`ws.closed::Observable{String}` fires the id of a panel whose close button (on a
closable tab or a floating window) was clicked — the workspace removes it for
you; listen if you need to clean up the panel's content too.

Mobile: below 700px viewport width the whole arrangement (docked tree *and*
floats) is *displayed* as a single tab group; the layout state is untouched and
comes back when the viewport widens. Tab dragging/floating is disabled there,
tapping switches.
"""
struct Workspace
    panels::Observable{Vector{Panel}}
    layout::Observable{Dict{String,Any}}
    meta::Observable{Dict{String,Any}}
    closed::Observable{String}
    min_fraction::Float64
    hide_single_tab::Bool
    style::Styles
end

# ── Layout helpers (pure data) ───────────────────────────────────────────────
"""
    tabgroup(ids::AbstractString...; active=first(ids))

A [`Workspace`](@ref) layout leaf: the given panel ids shown as tabs.
"""
function tabgroup(ids::AbstractString...; active::AbstractString=first(ids))
    active in ids || throw(ArgumentError("active=$active is not one of the panels"))
    return Dict{String,Any}("type" => "tabs", "panels" => collect(String, ids), "active" => String(active))
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

A [`Workspace`](@ref) layout node placing `children` side by side (left → right).
Children are [`tabgroup`](@ref)s or nested splits.
"""
hsplit(children...; fractions=fill(1.0 / length(children), length(children))) =
    splitnode("row", children; fractions)

"""
    vsplit(children...; fractions=equal)

A [`Workspace`](@ref) layout node stacking `children` (top → bottom).
"""
vsplit(children...; fractions=fill(1.0 / length(children), length(children))) =
    splitnode("column", children; fractions)

"""
    floatpanel(id; x=80, y=80, width=480, height=320)

A [`Workspace`](@ref) floating-window entry for the panel `id`.
"""
floatpanel(id::AbstractString; x::Integer=80, y::Integer=80, width::Integer=480, height::Integer=320) =
    Dict{String,Any}("panel" => String(id), "x" => Int(x), "y" => Int(y),
                     "width" => Int(width), "height" => Int(height))

"""
    workspacelayout(root; floating=[])

Assemble a full [`Workspace`](@ref) layout from a docked `root` node and a list
of [`floatpanel`](@ref) entries.
"""
workspacelayout(root::Dict{String,Any}; floating=Dict{String,Any}[]) =
    Dict{String,Any}("root" => root, "floating" => Any[floating...])

# All panel ids referenced anywhere in a layout (docked tree + floats).
function layout_panel_ids(layout::Dict{String,Any})
    ids = String[]
    _collect_node_ids!(ids, layout["root"])
    for f in get(layout, "floating", ())
        push!(ids, String(f["panel"]))
    end
    return ids
end
function _collect_node_ids!(ids, node)
    if node["type"] == "tabs"
        append!(ids, String.(node["panels"]))
    else
        for c in node["children"]
            _collect_node_ids!(ids, c)
        end
    end
    return ids
end

# Drop a panel id from the docked tree. Returns a (possibly nothing) node.
function node_drop_panel(node, id::AbstractString)
    if node["type"] == "tabs"
        panels = filter(!=(id), String.(node["panels"]))
        isempty(panels) && return nothing
        active = String(node["active"]) == id ? panels[1] : String(node["active"])
        return Dict{String,Any}("type" => "tabs", "panels" => panels, "active" => active)
    end
    kids = Any[]
    fracs = Float64[]
    for (c, f) in zip(node["children"], node["fractions"])
        k = node_drop_panel(c, id)
        if k !== nothing
            push!(kids, k)
            push!(fracs, f)
        end
    end
    isempty(kids) && return nothing
    length(kids) == 1 && return kids[1]
    s = sum(fracs)
    return Dict{String,Any}("type" => node["type"], "children" => kids, "fractions" => fracs ./ s)
end

# First tab-group leaf in document order.
function first_leaf(node)
    node["type"] == "tabs" && return node
    return first_leaf(node["children"][1])
end

layout_default(ids::AbstractVector{<:AbstractString}) =
    workspacelayout(isempty(ids) ? Dict{String,Any}("type" => "tabs", "panels" => String[], "active" => "") :
                    tabgroup(ids...))

# ── Construction ─────────────────────────────────────────────────────────────
function Workspace(items::AbstractVector;
                   layout::Union{Nothing,Dict{String,Any},Observable{Dict{String,Any}}}=nothing,
                   min_fraction::Real=0.1,
                   hide_single_tab::Bool=false,
                   style=Styles())
    isempty(items) && throw(ArgumentError("Workspace needs at least one panel"))
    panels = Panel[topanel(it) for it in items]
    ids = String[p.id for p in panels]
    allunique(ids) || throw(ArgumentError("panel ids must be unique, got $ids"))

    init = isnothing(layout) ? layout_default(ids) : layout
    layout_obs = init isa Observable ? init : Observable{Dict{String,Any}}(init)

    ws = Workspace(
        Observable(panels), layout_obs,
        Observable{Dict{String,Any}}(compute_meta(panels)),
        Observable(""), Float64(min_fraction), hide_single_tab, style,
    )
    # Close button on a closable tab/float removes the panel for us.
    on(ws.closed) do id
        isempty(id) && return
        any(p -> p.id == id, ws.panels[]) && remove_panel!(ws, id)
    end
    # Live label updates flow into meta without touching panel content.
    for p in panels
        wire_label!(ws, p)
    end
    return ws
end
Workspace(items...; kwargs...) = Workspace(collect(Any, items); kwargs...)

compute_meta(panels) = Dict{String,Any}(
    p.id => Dict{String,Any}("label" => p.label[], "closable" => p.closable) for p in panels)

refresh_meta!(ws::Workspace) = (ws.meta[] = compute_meta(ws.panels[]); nothing)

function wire_label!(ws::Workspace, p::Panel)
    on(p.label) do _
        any(q -> q.id == p.id, ws.panels[]) && refresh_meta!(ws)
    end
end

# ── Dynamic membership API ───────────────────────────────────────────────────
"""
    add_panel!(ws, panel; active=true) -> panel

Add a [`Panel`](@ref) (or `id => content` pair) to a live [`Workspace`](@ref),
docked as a tab in the first tab group. Pass `active=false` to add it without
focusing it. Use [`float_panel!`](@ref) to add it as a floating window instead.
If a panel with the same id already exists it is activated instead of duplicated.
"""
function add_panel!(ws::Workspace, panel; active::Bool=true)
    p = topanel(panel)
    if any(q -> q.id == p.id, ws.panels[])
        active && activate_panel!(ws, p.id)
        return p
    end
    ws.panels[] = push!(copy(ws.panels[]), p)
    wire_label!(ws, p)
    refresh_meta!(ws)
    lay = deepcopy(ws.layout[])
    leaf = first_leaf(lay["root"])
    push!(leaf["panels"], p.id)
    active && (leaf["active"] = p.id)
    ws.layout[] = lay
    return p
end

"""
    remove_panel!(ws, id)

Remove the panel `id` from a live [`Workspace`](@ref) — drops it from the docked
tree or floats and from `ws.panels` (its content node is removed from the DOM).
"""
function remove_panel!(ws::Workspace, id::AbstractString)
    id = String(id)
    lay = deepcopy(ws.layout[])
    root = node_drop_panel(lay["root"], id)
    lay["root"] = root === nothing ? Dict{String,Any}("type" => "tabs", "panels" => String[], "active" => "") : root
    lay["floating"] = Any[f for f in lay["floating"] if String(f["panel"]) != id]
    ws.layout[] = lay
    ws.panels[] = filter(p -> p.id != id, ws.panels[])
    refresh_meta!(ws)
    return nothing
end

"""
    activate_panel!(ws, id)

Make panel `id` the active tab of its group (no-op if it is floating or absent).
"""
function activate_panel!(ws::Workspace, id::AbstractString)
    id = String(id)
    lay = deepcopy(ws.layout[])
    changed = _activate!(lay["root"], id)
    changed && (ws.layout[] = lay)
    return nothing
end
function _activate!(node, id)
    if node["type"] == "tabs"
        if id in String.(node["panels"])
            node["active"] = id
            return true
        end
        return false
    end
    return any(c -> _activate!(c, id), node["children"])
end

"""
    float_panel!(ws, panel; x=80, y=80, width=480, height=320)

Float a panel into a window. `panel` may be an existing panel **id** (String)
to move a docked panel out, or a new [`Panel`](@ref)/`id => content` pair to add
and float in one step.
"""
function float_panel!(ws::Workspace, panel;
                      x::Integer=80, y::Integer=80, width::Integer=480, height::Integer=320)
    id = if panel isa AbstractString
        any(q -> q.id == String(panel), ws.panels[]) ||
            throw(ArgumentError("no panel with id $(panel) to float"))
        String(panel)
    else
        p = topanel(panel)
        if !any(q -> q.id == p.id, ws.panels[])
            ws.panels[] = push!(copy(ws.panels[]), p)
            wire_label!(ws, p)
            refresh_meta!(ws)
        end
        p.id
    end
    lay = deepcopy(ws.layout[])
    root = node_drop_panel(lay["root"], id)
    lay["root"] = root === nothing ? Dict{String,Any}("type" => "tabs", "panels" => String[], "active" => "") : root
    lay["floating"] = Any[f for f in lay["floating"] if String(f["panel"]) != id]
    push!(lay["floating"], floatpanel(id; x, y, width, height))
    ws.layout[] = lay
    return id
end

"""
    dock_panel!(ws, id; active=true)

Move a floating panel back into the docked tree (as a tab in the first group).
"""
function dock_panel!(ws::Workspace, id::AbstractString; active::Bool=true)
    id = String(id)
    lay = deepcopy(ws.layout[])
    any(f -> String(f["panel"]) == id, lay["floating"]) || return nothing
    lay["floating"] = Any[f for f in lay["floating"] if String(f["panel"]) != id]
    leaf = first_leaf(lay["root"])
    id in leaf["panels"] || push!(leaf["panels"], id)
    active && (leaf["active"] = id)
    ws.layout[] = lay
    return nothing
end

# ── Rendering ────────────────────────────────────────────────────────────────
function Bonito.jsrender(session::Session, ws::Workspace)
    # Each panel's content renders ONCE. The current panels are inlined into the
    # parking pool (so they exist on first paint and measure real dimensions);
    # the wire script then *moves* the nodes into leaf bodies and floats — never
    # re-renders them. Panels added later are shipped in via `dom_in_js` and
    # appended to the pool; removed panels are pruned by the wire's render().
    parking = DOM.div(
        (PanelView(p) for p in ws.panels[])...;
        class="bw-ws-parking",
        style=Styles("flex" => "1 1 0", "position" => "relative",
                     "min-width" => "0", "min-height" => "0"))
    chrome = DOM.div(;
        class="bw-ws-chrome",
        style=Styles("flex" => "1 1 0", "display" => "none",
                     "min-width" => "0", "min-height" => "0"))
    floatlayer = DOM.div(; class="bw-ws-floatlayer")

    # Ship panels added after the initial render into the pool. (Appends only;
    # placement/removal is the wire's job, keyed by the layout observable.)
    shipped = Set{String}(p.id for p in ws.panels[])
    on(session, ws.panels) do ps
        for p in ps
            p.id in shipped && continue
            push!(shipped, p.id)
            Bonito.dom_in_js(session, PanelView(p), js"""(el) => {
                const pool = $(parking);
                pool.appendChild(el);
                const root = pool.closest('.bw-ws');
                if (root && root.__bwScheduleRender) root.__bwScheduleRender();
            }""")
        end
    end

    wire = js"""
    (() => {
        const chrome = $(chrome);
        const wsRoot = chrome.closest('.bw-ws');
        const parking = $(parking);
        const floatlayer = $(floatlayer);
        const layoutObs = $(ws.layout);
        const metaObs = $(ws.meta);
        const closedObs = $(ws.closed);
        const minFrac = $(ws.min_fraction);
        const hideSingleTab = $(ws.hide_single_tab);

        const ICON_CLOSE = '<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"></path></svg>';
        const ICON_DOCK = '<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="1.5"></rect><path d="M8 4.5v5M5.5 7L8 9.5 10.5 7"></path></svg>';

        const clone = (x) => JSON.parse(JSON.stringify(x));
        let layout = clone(layoutObs.value);     // {root, floating}
        let meta = metaObs.value || {};
        const narrow = window.matchMedia('(max-width: 700px)');

        const labelOf = (id) => (meta[id] && meta[id].label != null) ? meta[id].label : id;
        const closableOf = (id) => !!(meta[id] && meta[id].closable);
        const panelNode = (id) =>
            wsRoot.querySelector('.bw-ws-panel[data-panel-id="' + (window.CSS ? CSS.escape(id) : id) + '"]');

        // ---- tree helpers (operate on layout.root) --------------------------
        const isLeaf = (node) => node.type === 'tabs';
        function leafOf(node, id) {
            if (isLeaf(node)) return node.panels.includes(id) ? node : null;
            for (const c of node.children) { const f = leafOf(c, id); if (f) return f; }
            return null;
        }
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
        function firstActive() {
            let node = layout.root;
            while (!isLeaf(node)) node = node.children[0];
            return node.active;
        }
        const floatOf = (id) => layout.floating.find(f => f.panel === id) || null;

        // ---- rendering ------------------------------------------------------
        let suppressClick = false;
        let suppressRender = false;

        // Switch the active tab WITHOUT a full re-render: a full render parks
        // every panel through the display:none pool, which collapses scrollable
        // content (chat, editors) to height 0 and resets its scrollTop. An
        // in-place visibility toggle preserves scroll + is far cheaper.
        function setActiveLocal(leaf, id) {
            leaf.active = id;
            for (const g of chrome.querySelectorAll('.bw-ws-group')) {
                if (g._node !== leaf) continue;
                for (const b of g._strip.children) b.classList.toggle('bw-active', b._panelId === id);
                leaf.panels.forEach((pid) => {
                    const node = panelNode(pid);
                    if (node && g._body.contains(node)) {
                        const on = pid === id;
                        node.style.visibility = on ? 'visible' : 'hidden';
                        node.style.pointerEvents = on ? 'auto' : 'none';
                    }
                });
                return;
            }
        }

        function parkAll() {
            wsRoot.querySelectorAll('.bw-ws-panel').forEach(p => {
                if (p.parentNode !== parking) parking.appendChild(p);
            });
        }

        function placePanel(body, id, activeId) {
            const p = panelNode(id);
            if (!p) return;
            body.appendChild(p);
            const on = id === activeId;
            p.style.visibility = on ? 'visible' : 'hidden';
            p.style.pointerEvents = on ? 'auto' : 'none';
        }

        function buildLeaf(leaf, bare) {
            const group = document.createElement('div');
            group.className = 'bw-ws-group';
            const bar = document.createElement('div');
            bar.className = 'bw-group-bar';
            const strip = document.createElement('div');
            strip.className = 'bw-group-tabs';
            bar.appendChild(strip);
            const body = document.createElement('div');
            body.className = 'bw-ws-body';
            // `bare`: a lone panel with nothing to manage — drop the tab bar so
            // the content goes full-bleed (the body still wires up as a drop
            // target via group._strip/_body).
            if (!bare) group.appendChild(bar);
            group.appendChild(body);
            group._node = leaf;
            group._strip = strip;
            group._body = body;

            leaf.panels.forEach((id) => {
                const btn = document.createElement('button');
                btn.className = id === leaf.active ? 'bw-tab bw-active' : 'bw-tab';
                btn._panelId = id;
                const text = document.createElement('span');
                text.className = 'bw-tab-label';
                text.textContent = labelOf(id);
                btn.appendChild(text);
                if (closableOf(id)) {
                    const close = document.createElement('button');
                    close.className = 'bw-tab-close';
                    close.innerHTML = ICON_CLOSE;
                    close.title = 'Close';
                    close.addEventListener('pointerdown', (e) => e.stopPropagation());
                    close.addEventListener('click', (e) => { e.stopPropagation(); closedObs.notify(id); });
                    btn.appendChild(close);
                }
                btn.addEventListener('click', () => {
                    if (suppressClick) { suppressClick = false; return; }
                    if (leaf.active === id) return;
                    setActiveLocal(leaf, id);   // in-place: preserves scroll
                    notifyLayout(true);          // persist without a full re-render
                });
                if (!narrow.matches) btn.addEventListener('pointerdown', (e) => startTabDrag(e, id, btn));
                strip.appendChild(btn);
                placePanel(body, id, leaf.active);
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

            let dragging = false, combinedStart = 0, combinedSize = 0, total = 0, elA = null, elB = null;
            gutter.addEventListener('pointerdown', (e) => {
                elA = splitEl.children[2 * i];
                elB = splitEl.children[2 * i + 2];
                const ra = elA.getBoundingClientRect();
                const rb = elB.getBoundingClientRect();
                if (node.type === 'row') { combinedStart = ra.left; combinedSize = rb.right - ra.left; }
                else { combinedStart = ra.top; combinedSize = rb.bottom - ra.top; }
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

        // Floating window chrome — reuses the .bw-float visuals but positioned
        // absolute within the workspace (not fixed to the viewport).
        function buildFloat(f) {
            const win = document.createElement('div');
            win.className = 'bw-float bw-ws-float';
            win._float = f;
            const titleBar = document.createElement('div');
            titleBar.className = 'bw-float-title';
            const titleText = document.createElement('span');
            titleText.className = 'bw-float-title-text';
            titleText.textContent = labelOf(f.panel);
            const dockBtn = document.createElement('button');
            dockBtn.className = 'bw-icon-btn bw-float-dock';
            dockBtn.innerHTML = ICON_DOCK;
            dockBtn.title = 'Dock';
            const closeBtn = document.createElement('button');
            closeBtn.className = 'bw-icon-btn bw-float-close';
            closeBtn.innerHTML = ICON_CLOSE;
            closeBtn.title = closableOf(f.panel) ? 'Close' : 'Dock';
            titleBar.appendChild(titleText);
            titleBar.appendChild(dockBtn);
            titleBar.appendChild(closeBtn);
            const body = document.createElement('div');
            body.className = 'bw-float-body';
            const resize = document.createElement('div');
            resize.className = 'bw-float-resize';
            resize.title = 'Drag to resize';
            win.appendChild(titleBar);
            win.appendChild(body);
            win.appendChild(resize);
            win.style.left = f.x + 'px';
            win.style.top = f.y + 'px';
            win.style.width = f.width + 'px';
            win.style.height = f.height + 'px';

            const p = panelNode(f.panel);
            if (p) {
                body.appendChild(p);
                p.style.visibility = 'visible';
                p.style.pointerEvents = 'auto';
            }

            dockBtn.addEventListener('click', (e) => { e.stopPropagation(); dockFloat(f.panel); });
            closeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                if (closableOf(f.panel)) closedObs.notify(f.panel);
                else dockFloat(f.panel);
            });
            wireFloatDrag(win, titleBar, f);
            wireFloatResize(win, resize, f);
            return win;
        }

        // Ids ever placed by a prior render — lets us prune nodes whose panel
        // was removed without deleting a freshly-shipped node that hasn't made
        // it into the layout yet.
        let placedIds = new Set();

        function render() {
            parkAll();
            const layoutIds = new Set(allPanels(layout.root).concat(layout.floating.map(f => f.panel)));
            // Prune DOM nodes for panels removed from the layout.
            wsRoot.querySelectorAll('.bw-ws-panel').forEach((p) => {
                const id = p.dataset.panelId;
                if (!layoutIds.has(id) && placedIds.has(id)) p.remove();
            });
            if (narrow.matches) {
                const ids = allPanels(layout.root).concat(layout.floating.map(f => f.panel));
                const active = ids.length ? (ids.includes(firstActive()) ? firstActive() : ids[0]) : '';
                // Same bar-less rule on mobile: a lone panel needs no tab strip.
                chrome.replaceChildren(buildLeaf({ type: 'tabs', panels: ids, active },
                    hideSingleTab && ids.length === 1));
                floatlayer.replaceChildren();
            } else {
                // A lone non-managed panel renders bar-less when hideSingleTab
                // is set: single tab group, single panel, no floating windows.
                const bareRoot = hideSingleTab && isLeaf(layout.root) &&
                    layout.root.panels.length === 1 && layout.floating.length === 0;
                chrome.replaceChildren(bareRoot ? buildLeaf(layout.root, true) : buildNode(layout.root));
                floatlayer.replaceChildren(...layout.floating.map(buildFloat));
            }
            placedIds = layoutIds;
            const rootEl = chrome.firstElementChild;
            if (rootEl) rootEl.style.flex = '1 1 0';
            chrome.style.display = 'flex';
            parking.style.display = 'none';
        }

        // `local` notifies the layout for persistence but skips the self-render
        // (the caller already updated the DOM in place — e.g. a tab switch).
        function notifyLayout(local) {
            if (local) suppressRender = true;
            layoutObs.notify(clone(layout));
            suppressRender = false;
        }

        let renderQueued = false;
        const scheduleRender = () => {
            if (renderQueued) return;
            renderQueued = true;
            requestAnimationFrame(() => { renderQueued = false; render(); });
        };
        // Julia ships dynamically-added panel nodes into the pool, then calls
        // this to place them.
        wsRoot.__bwScheduleRender = scheduleRender;

        layoutObs.on((v) => { layout = clone(v); if (suppressRender) return; render(); });
        metaObs.on((m) => { meta = m || {}; render(); });
        const onNarrow = () => render();
        if (narrow.addEventListener) narrow.addEventListener('change', onNarrow);
        else narrow.addListener(onNarrow);

        // ---- drop targeting (shared by tab drag + float drag) ---------------
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

        // Returns a drop action or null. kinds: 'strip', 'center', edge sides,
        // or 'float' (pointer outside the docked chrome).
        function dropActionAt(e, allowFloat) {
            for (const group of chrome.querySelectorAll('.bw-ws-group')) {
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
            if (allowFloat) {
                const cr = chrome.getBoundingClientRect();
                if (e.clientX < cr.left || e.clientX > cr.right ||
                    e.clientY < cr.top || e.clientY > cr.bottom) {
                    return { kind: 'float' };
                }
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
            if (action.kind === 'float') {
                overlay.style.display = 'none';
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

        // Insert panel `id` (already removed from wherever it was) per `action`.
        function dockInto(id, action) {
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
                layout.root = replaceNode(layout.root, action.leaf, split);
            }
        }

        // ---- tab dragging (move within tree / tear out to float) ------------
        function applyTabDrop(id, action) {
            const src = leafOf(layout.root, id);
            if (action.kind !== 'float' && action.leaf === src && src.panels.length === 1 &&
                (action.kind === 'center' || action.kind === 'strip')) return;
            src.panels = src.panels.filter(p => p !== id);
            if (src.active === id) src.active = src.panels[0] || '';
            if (action.kind === 'float') {
                const wr = wsRoot.getBoundingClientRect();
                const x = Math.max(0, Math.round(action.clientX - wr.left - 40));
                const y = Math.max(0, Math.round(action.clientY - wr.top - 16));
                layout.floating.push({ panel: id, x, y, width: 480, height: 320 });
            } else {
                dockInto(id, action);
            }
            layout.root = normalize(layout.root) || { type: 'tabs', panels: [], active: '' };
            notifyLayout();
        }

        function startTabDrag(e, id, btn) {
            if (e.button !== undefined && e.button !== 0) return;
            const startX = e.clientX, startY = e.clientY;
            let engaged = false, ghost = null, action = null;
            const onMove = (e2) => {
                if (!engaged) {
                    if (Math.hypot(e2.clientX - startX, e2.clientY - startY) < 6) return;
                    engaged = true;
                    btn.classList.add('bw-drag-src');
                    ghost = document.createElement('div');
                    ghost.className = 'bw-drag-ghost';
                    ghost.textContent = labelOf(id);
                    document.body.appendChild(ghost);
                }
                ghost.style.left = (e2.clientX + 10) + 'px';
                ghost.style.top = (e2.clientY + 14) + 'px';
                action = dropActionAt(e2, true);
                if (action && action.kind === 'float') { action.clientX = e2.clientX; action.clientY = e2.clientY; }
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
                if (apply && action) applyTabDrop(id, action);
            };
            const onUp = () => finish(true);
            const onCancel = () => finish(false);
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
            window.addEventListener('pointercancel', onCancel);
        }

        // ---- floating windows ----------------------------------------------
        const wsRect = () => wsRoot.getBoundingClientRect();
        const clampFloatX = (x) => Math.max(0, Math.min(wsRoot.clientWidth - 48, x));
        const clampFloatY = (y) => Math.max(0, Math.min(wsRoot.clientHeight - 32, y));

        function dockFloat(id, action) {
            layout.floating = layout.floating.filter(f => f.panel !== id);
            if (action) dockInto(id, action);
            else { const leaf = firstLeafNode(); leaf.panels.push(id); leaf.active = id; }
            layout.root = normalize(layout.root) || { type: 'tabs', panels: [id], active: id };
            notifyLayout();
        }
        function firstLeafNode() {
            let node = layout.root;
            while (!isLeaf(node)) node = node.children[0];
            return node;
        }

        function wireFloatDrag(win, titleBar, f) {
            titleBar.addEventListener('pointerdown', (ev) => {
                if (ev.target.closest('.bw-float-close, .bw-float-dock')) return;
                if (ev.button !== undefined && ev.button !== 0) return;
                win.classList.add('bw-float-active');
                const rect = wsRect();
                const offX = ev.clientX - (f.x + rect.left);
                const offY = ev.clientY - (f.y + rect.top);
                let lastX = f.x, lastY = f.y, action = null;
                const onMove = (e2) => {
                    const r = wsRect();
                    lastX = clampFloatX(e2.clientX - r.left - offX);
                    lastY = clampFloatY(e2.clientY - r.top - offY);
                    win.style.left = lastX + 'px';
                    win.style.top = lastY + 'px';
                    // Docking preview only when over a strip or an edge zone.
                    const a = dropActionAt(e2, false);
                    action = (a && a.kind !== 'center') ? a : null;
                    showAction(action);
                };
                const onUp = () => {
                    window.removeEventListener('pointermove', onMove);
                    window.removeEventListener('pointerup', onUp);
                    overlay.style.display = 'none';
                    clearMark();
                    win.classList.remove('bw-float-active');
                    if (action) { dockFloat(f.panel, action); return; }
                    f.x = Math.round(lastX); f.y = Math.round(lastY);
                    notifyLayout();
                };
                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onUp);
                ev.preventDefault();
            });
        }

        function wireFloatResize(win, handle, f) {
            handle.addEventListener('pointerdown', (ev) => {
                const startW = win.offsetWidth, startH = win.offsetHeight;
                const startX = ev.clientX, startY = ev.clientY;
                let lastW = startW, lastH = startH;
                const onMove = (e2) => {
                    lastW = Math.max(200, Math.min(wsRoot.clientWidth, startW + (e2.clientX - startX)));
                    lastH = Math.max(120, Math.min(wsRoot.clientHeight, startH + (e2.clientY - startY)));
                    win.style.width = lastW + 'px';
                    win.style.height = lastH + 'px';
                };
                const onUp = () => {
                    window.removeEventListener('pointermove', onMove);
                    window.removeEventListener('pointerup', onUp);
                    f.width = Math.round(lastW); f.height = Math.round(lastH);
                    notifyLayout();
                };
                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onUp);
                ev.preventDefault(); ev.stopPropagation();
            });
        }

        render();
    })();
    """

    container = DOM.div(
        THEME_STYLES, ICON_BUTTON_STYLES, TABS_STYLES, SPLIT_STYLES,
        PANEL_GROUP_STYLES, FLOATING_STYLES, WORKSPACE_STYLES,
        chrome, parking, floatlayer, DOM.script(wire);
        class="bw-ws",
        style=Styles(ws.style,
            "position" => "relative",
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
        "display" => "flex", "flex-direction" => "column",
        "min-width" => "0", "min-height" => "0", "overflow" => "hidden",
    ),
    CSS(".bw-ws-body",
        "flex" => "1 1 0", "position" => "relative",
        "min-width" => "0", "min-height" => "0", "overflow" => "hidden",
        "background-color" => "var(--bw-bg-panel)",
    ),
    CSS(".bw-ws .bw-group-tabs > .bw-tab", "touch-action" => "pan-x"),
    CSS(".bw-ws-chrome.bw-dragging", "user-select" => "none"),
    CSS(".bw-ws-chrome.bw-dragging .bw-ws-body", "pointer-events" => "none"),
    # Floating layer sits above the docked chrome; the layer itself is
    # click-through, only its windows capture pointers.
    CSS(".bw-ws-floatlayer",
        "position" => "absolute", "inset" => "0",
        "pointer-events" => "none", "z-index" => "var(--bw-z-float)",
    ),
    CSS(".bw-ws-float",
        "position" => "absolute", "pointer-events" => "auto",
    ),
    CSS(".bw-ws-float.bw-float-active", "z-index" => "1"),
    CSS(".bw-tab-label", "min-width" => "0", "overflow" => "hidden",
        "text-overflow" => "ellipsis", "white-space" => "nowrap"),
    CSS(".bw-ws .bw-tab-close",
        "display" => "inline-flex", "align-items" => "center", "justify-content" => "center",
        "padding" => "0",
        "width" => "16px", "height" => "16px", "flex" => "0 0 auto",
        "background" => "transparent", "border" => "none", "border-radius" => "var(--bw-radius-sm)",
        "color" => "var(--bw-text-muted)", "cursor" => "pointer",
        "line-height" => "0",
    ),
    # Slightly tighter label↔close spacing for the workspace's denser tabs.
    CSS(".bw-ws .bw-group-tabs > .bw-tab", "gap" => "var(--bw-space-1)"),
)
