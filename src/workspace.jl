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
  a **floating window**.
- A floating window's title bar only **moves** it — dragging one across the
  workspace never docks it. Docking is the **dock button** in its title bar:
  click it to send the panel back to the group it was torn out of, or drag from
  it to aim at any group or edge (same preview a tab drag gets).
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
- `<float>` is `Dict("panel"=>id, "x"=>, "y"=>, "width"=>, "height"=>)`. Tearing a
  tab out also records `"home"=>id`, a panel left behind in the source group, so
  the dock button can send it back there; it is optional and safe to omit.

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
# The BonitoWidgets client module (workspace layout engine). Loaded once as a
# hashed static asset; `mountWorkspace` is called with the workspace's DOM
# regions + state observables (see `jsrender` below).
const WorkspaceLib = Bonito.ES6Module(joinpath(@__DIR__, "..", "assets", "BonitoWidgets.js"))

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
        # Reconcile first: drop ids no longer present so a panel that was REMOVED
        # and later re-added under the SAME id re-ships its freshly-rendered
        # content node. Without this, `p.id in shipped` skips the re-add forever
        # and the panel never appears — e.g. detach an app / open a file, close
        # it, then do it again (the old node was pruned from the DOM by the wire,
        # so there is nothing left to show).
        cur = Set{String}(p.id for p in ps)
        filter!(id -> id in cur, shipped)
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


    container = DOM.div(
        THEME_STYLES, ICON_BUTTON_STYLES, TABS_STYLES, SPLIT_STYLES,
        PANEL_GROUP_STYLES, FLOATING_STYLES, WORKSPACE_STYLES,
        chrome, parking, floatlayer;
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
    # The layout engine lives in the BonitoWidgets ES6 module (loads once as a
    # static asset; stays interactive under `export_static`, unlike an inline
    # `js""`). We hand it the DOM regions + the state observables; it owns the
    # drag/dock/float/split logic and only `notify`s state back.
    Bonito.onload(session, container, js"""(root) => {
        $(WorkspaceLib).then(lib => lib.mountWorkspace({
            chrome: $(chrome),
            parking: $(parking),
            floatlayer: $(floatlayer),
            layout: $(ws.layout),
            meta: $(ws.meta),
            closed: $(ws.closed),
            minFraction: $(ws.min_fraction),
            hideSingleTab: $(ws.hide_single_tab),
        }));
    }""")
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
