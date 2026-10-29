# An endless list: rows load in chunks as they scroll into reach, and rows far
# out of view leave the page.

"""
The browser side of endless lists (`assets/row_block.js`): `RowBlock`, the
engine, and `InfiniteList`. Apps with their own rows build on `RowBlock`
directly; BonitoAgents' chat transcript does.
"""
const ROW_BLOCK_LIB = Bonito.ES6Module(joinpath(@__DIR__, "..", "assets", "row_block.js"))

"""
    items(source, range::UnitRange{Int}) -> AbstractVector

The items of `source` at positions `range` (1-based), fewer at its end. The
data protocol of an [`InfiniteList`](@ref): add a method for your source type.
Vectors have one.
"""
items(v::AbstractVector, range::UnitRange{Int}) =
    v[max(first(range), firstindex(v)):min(last(range), lastindex(v))]

"""
    row(source, item) -> renderable

How an [`InfiniteList`](@ref) over `source` shows `item`: the item itself by
default. Rows are static HTML, so a row carries no observables; give rows
`data-*` attributes and handle clicks on an ancestor instead.
"""
row(source, item) = item

# A row as HTML. A DOM node is HTML already; anything else (a string, say) goes
# into a div, which escapes it.
row_html(node::Bonito.HTMLElement) = string(node)
row_html(x) = string(DOM.div(x))

"""
    InfiniteList(source; chunk = 50, window = 200, class = "")

An endless list over `source`: rows load `chunk` at a time as they come into
reach, and past `window` rows the ones farthest out of view leave the page, so
a list of any length stays light. `source` is anything with a method of
[`BonitoWidgets.items`](@ref); rows render through [`BonitoWidgets.row`](@ref).
Setting `list.source[]` starts the list over at the top. Render a list once
per page: its rows answer that page's requests.

```julia
list = InfiniteList(["Row \$i" for i in 1:100_000]; class = "my-list")
```
"""
struct InfiniteList
    source::Observable{Any}
    chunk::Int
    window::Int
    class::String
    to_julia::Observable{Dict{String,Any}}
    to_js::Observable{Dict{String,Any}}
end

function InfiniteList(source; chunk::Integer = 50, window::Integer = 200, class::AbstractString = "")
    window > chunk || throw(ArgumentError("window ($window) must hold more than one chunk ($chunk)"))
    list = InfiniteList(Observable{Any}(source), chunk, window, String(class),
                        Observable(Dict{String,Any}()), Observable(Dict{String,Any}()))
    on(_ -> list.to_js[] = Dict{String,Any}("type" => "reset"), list.source)
    return list
end

"""
    handle_request!(list, msg)

Answer the browser's `{type: "request", epoch, req, start, stop}` (0-based,
inclusive) with the rows at those positions, fewer at the source's end.
"""
function handle_request!(list::InfiniteList, msg::AbstractDict)
    msg["type"] == "request" || error("InfiniteList: unknown message type $(repr(msg["type"]))")
    source = list.source[]
    found = items(source, (msg["start"] + 1):(msg["stop"] + 1))
    list.to_js[] = Dict{String,Any}(
        "type" => "rows", "epoch" => msg["epoch"], "req" => msg["req"], "start" => msg["start"],
        "rows" => String[row_html(row(source, x)) for x in found])
    return
end

function Bonito.jsrender(session::Session, list::InfiniteList)
    on(msg -> handle_request!(list, msg), session, list.to_julia)
    rows = DOM.div(; class = "bw-infinite-list-rows")
    # The scroller is the rows' parent: a script can't name the node it sits in.
    wire = js"""$(ROW_BLOCK_LIB).then(lib => new lib.InfiniteList($(rows).parentElement, $(rows),
        $(list.to_julia), $(list.to_js), {chunk: $(list.chunk), window: $(list.window)}))"""
    scroller = DOM.div(INFINITE_LIST_STYLES, rows, wire;
                       class = isempty(list.class) ? "bw-infinite-list" : "bw-infinite-list " * list.class)
    return Bonito.jsrender(session, scroller)
end

const INFINITE_LIST_STYLES = Styles(
    # Positioned, so a row's offsetTop is measured in the scroller's content.
    # overflow-anchor: none, because the list anchors the scroll position itself
    # (rows loaded or dropped above the reader); with the browser's anchoring
    # on as well, two systems would correct the same position.
    CSS(".bw-infinite-list",
        "position" => "relative", "overflow-y" => "auto", "overflow-anchor" => "none",
        "min-height" => "0"),
)
