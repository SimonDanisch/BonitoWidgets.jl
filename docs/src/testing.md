# Testing layouts

The [walkthrough video](@ref BonitoWidgets) on the home page is a real Electron
window driven from code: steering plots, splitting the layout by dragging a tab
to a group edge, floating a panel and docking it back. It was recorded with
[ElectronCall](https://github.com/SimonDanisch/ElectronCall.jl). Source:
[`examples/walkthrough.jl`](https://github.com/SimonDanisch/BonitoWidgets.jl/blob/master/examples/walkthrough.jl).

## Probes

The layout moves as panels split and float, so tests can't use fixed pixels.
BonitoWidgets ships a few unexported probe helpers that build a small JavaScript
expression to find a point on a widget by its label, against the live DOM, and
return `[x, y]`, or `null` if nothing matches:

- `tab(label)`: the tab button whose label starts with `label`
- `groupbody(label; rel=(0.5, 0.9))`: a point in the body of the group that
  holds that tab (the edges are the drop zones for splitting)
- `floattitle(label)`: the title bar of the floating window named `label`

They only use the widgets' CSS classes, so they don't pull in a test driver.
Pull them in explicitly:

```julia
using BonitoWidgets: tab, groupbody, floattitle
```

## With ElectronCall

Any driver that can run JS and return a point can use a probe. With ElectronCall,
wrap the expression in its `JS` target and pass it to the event DSL:

```julia
using BonitoWidgets: tab, groupbody, floattitle
using ElectronCall.Testing      # JS, Click, Drag, play, ...

play(ctx, [
    Click(JS(tab("Waveform"))),                                       # switch tabs
    Drag(JS(tab("Field")), JS(groupbody("Field"; rel=(0.5, 0.9)))),   # split off the bottom
    Drag(JS(floattitle("Surface")), JS(tab("Phase Portrait"))),       # dock a floating window
])
```

The probes are resolved at play time, so each drag lands wherever the panel is
at that moment, even after earlier steps have moved things around.
