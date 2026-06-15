# DOM probe builders for UI tests. As panels split and float, a test can't use
# fixed pixels, so these build a JS expression that finds a point on a widget by
# its label and returns `[x, y]`, or `null` if nothing matches. They are
# unexported; pull them in explicitly and pass the result to a driver. With
# ElectronCall that is the `JS` target:
#
#     using BonitoWidgets: tab, groupbody, floattitle
#     using ElectronCall.Testing            # JS, Drag, Click, play, ...
#     play(ctx, [Click(JS(tab("Waveform"))),
#                Drag(JS(tab("Field")), JS(groupbody("Field"; rel = (0.5, 0.9))))])

js_selector(::Nothing) = "null"
js_selector(sel::AbstractString) = repr(sel)   # repr gives a quoted, escaped JS string literal

# Find the element under `container` whose label text starts with `label` (the
# container itself, or a `label_in` descendant), then take a point at
# `rel`+`offset` in the rect of `rect_in` (or the container).
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

JS for a point in the body of the group holding tab `label`. The edges are drop
zones; `rel = (0.5, 0.9)` is the bottom edge, which splits the layout.
"""
groupbody(label::AbstractString; rel = (0.5, 0.5), offset = (0.0, 0.0)) =
    probe_js(".bw-ws-group", ".bw-tab", ".bw-ws-body", label, rel, offset)

"""
    floattitle(label; rel = (0, 0.5), offset = (40, 0)) -> String

JS for the title bar of the floating window titled `label`. Defaults to the left
edge, clear of the close button, which is a good place to grab for a drag.
"""
floattitle(label::AbstractString; rel = (0.0, 0.5), offset = (40.0, 0.0)) =
    probe_js(".bw-ws-float", ".bw-float-title-text", ".bw-float-title", label, rel, offset)
