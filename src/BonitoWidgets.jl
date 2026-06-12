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

export Theme
export Tabs
export SplitContainer
export Collapsible
export PanelGroup
export Workspace, tabgroup, hsplit, vsplit
export FloatingWindow
export IconButton, OrientationToggle, CollapseButton

end
