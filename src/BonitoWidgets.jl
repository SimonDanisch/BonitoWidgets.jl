module BonitoWidgets

using Bonito
using Bonito: Styles, CSS, Session
using Observables

include("theme.jl")
include("icons.jl")
include("widgets.jl")
include("tabs.jl")
include("split.jl")
include("collapsible.jl")
include("panelgroup.jl")
include("workspace.jl")
include("floating.jl")
include("probes.jl")  # unexported JS DOM-probe builders for driver-agnostic UI tests

export Theme
export Tabs
export SplitContainer
export Collapsible
export PanelGroup
export Workspace, Panel, tabgroup, hsplit, vsplit, floatpanel, workspacelayout
export add_panel!, remove_panel!, float_panel!, dock_panel!, activate_panel!
export FloatingWindow
export IconButton, OrientationToggle, CollapseButton

end
