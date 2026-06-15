# Testing layouts

The [walkthrough video](@ref BonitoWidgets) on the home page is a real Electron
window driven entirely by code — steering live plots, splitting the layout by
dragging a tab to a group edge, docking a floating window, then tearing a tab
back out — captured with
[ElectronCall](https://github.com/SimonDanisch/ElectronCall.jl)'s
animated-cursor recorder. Source: [`examples/walkthrough.jl`](https://github.com/SimonDanisch/BonitoWidgets.jl/blob/master/examples/walkthrough.jl).

## Probes

Because the layout rearranges itself as panels split and float, an end-to-end
test can't hard-code pixels. BonitoWidgets ships a handful of **unexported probe
helpers** that build a tiny JavaScript expression locating a point on a widget
*by label*, against the live DOM, returning `[x, y]` (or `null`):

- `tab(label)` — the tab button whose label starts with `label`
- `groupbody(label; rel=(0.5, 0.9))` — a fractional point in the body of the
  group holding that tab (the edges are the split drop zones)
- `floattitle(label)` — the title bar of the floating window titled `label`

They depend only on the widgets' own CSS classes — no test-driver dependency.
Pull them in explicitly:

```julia
using BonitoWidgets: tab, groupbody, floattitle
```

## With ElectronCall

Any driver that can evaluate JS and return a point can use a probe. With
ElectronCall, wrap the expression in its generic `JS` target and it slots
straight into the event DSL:

```julia
using BonitoWidgets: tab, groupbody, floattitle
using ElectronCall.Testing      # JS, Click, Drag, play, ...

play(ctx, [
    Click(JS(tab("Waveform"))),                                       # switch tabs
    Drag(JS(tab("Field")), JS(groupbody("Field"; rel=(0.5, 0.9)))),   # split off the bottom
    Drag(JS(floattitle("Surface")), JS(tab("Phase Portrait"))),       # dock a floating window
])
```

The probes are resolved at play time, so each drag lands wherever the panel
currently is — exactly what makes a script survive the layout rearranging
itself mid-run.
