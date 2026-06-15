# DOM probe builders for end-to-end UI tests. As the layout rearranges (tabs
# reorder, panels split, windows float), a test can't hard-code pixels — these
# build a JS expression that locates a point *by label* against the rendered
# DOM, returning `[x, y]` or `null`. Unexported; pull them in explicitly and
# feed the result to a driver — with ElectronCall that's the generic `JS` target:
#
#     using BonitoWidgets: tab, groupbody, floattitle
#     using ElectronCall.Testing            # JS, Drag, Click, play, ...
#     play(ctx, [Click(JS(tab("Waveform"))),
#                Drag(JS(tab("Field")), JS(groupbody("Field"; rel = (0.5, 0.9))))])

js_selector(::Nothing) = "null"
js_selector(sel::AbstractString) = repr(sel)   # repr → a quoted, escaped JS string literal

# Find the element under `container` whose label text starts with `label` (the
# container itself, or a `label_in` descendant), then a point at `rel`+`offset`
# in the rect of `rect_in` (or the container).
function probe_js(container::AbstractString, label_in, rect_in,
                  label::AbstractString, rel, offset)
    fx, fy = Float64(rel[1]), Float64(rel[2])
    ox, oy = Float64(offset[1]), Float64(offset[2])
    """
    (() => {
        const startsWith = el => el && el.textContent.trim().startsWith($(repr(label)));
        const labelIn = $(js_selector(label_in));
        const rectIn  = $(js_selector(rect_in));
        const container = [...document.querySelectorAll($(js_selector(container)))]
            .find(c => labelIn ? [...c.querySelectorAll(labelIn)].some(startsWith) : startsWith(c));
        if (!container) return null;
        const box = rectIn ? container.querySelector(rectIn) : container;
        if (!box) return null;
        const r = box.getBoundingClientRect();
        return [r.x + $(fx) * r.width + $(ox), r.y + $(fy) * r.height + $(oy)];
    })()
    """
end

"""
    tab(label; rel = (0.5, 0.5), offset = (0, 0)) -> String

JS for the tab button whose label starts with `label` (its centre by default).
"""
tab(label::AbstractString; rel = (0.5, 0.5), offset = (0.0, 0.0)) =
    probe_js(".bw-tab", nothing, nothing, label, rel, offset)

"""
    groupbody(label; rel = (0.5, 0.5), offset = (0, 0)) -> String

JS for a point in the body of the group holding tab `label`; the edges are drop
zones (`rel = (0.5, 0.9)` → bottom → splits the layout).
"""
groupbody(label::AbstractString; rel = (0.5, 0.5), offset = (0.0, 0.0)) =
    probe_js(".bw-ws-group", ".bw-tab", ".bw-ws-body", label, rel, offset)

"""
    floattitle(label; rel = (0, 0.5), offset = (40, 0)) -> String

JS for the title bar of the floating window titled `label` (left edge by
default, clear of the close button) — the grab point for a drag.
"""
floattitle(label::AbstractString; rel = (0.0, 0.5), offset = (40.0, 0.0)) =
    probe_js(".bw-ws-float", ".bw-float-title-text", ".bw-float-title", label, rel, offset)
