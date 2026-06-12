# Kitchen-sink demo of all BonitoWidgets components.
# Run with:
#   julia> app = include("dev/BonitoWidgets/examples/demo.jl")
#   julia> server = Bonito.Server(app, "0.0.0.0", 8765)
using Bonito, BonitoWidgets

function placeholder(label, color)
    return DOM.div(label;
        style=Styles(
            "display" => "flex", "align-items" => "center", "justify-content" => "center",
            "width" => "100%", "height" => "100%", "min-height" => "60px",
            "background" => color, "color" => "white",
            "font-family" => "var(--bw-font)", "font-size" => "18px",
        ))
end

function caption(text, widgets...)
    return DOM.div(
        DOM.span(text; style=Styles(
            "font-family" => "var(--bw-font)", "font-size" => "var(--bw-font-size-sm)",
            "color" => "var(--bw-text-muted)")),
        widgets...;
        style=Styles("display" => "flex", "align-items" => "center", "gap" => "8px"),
    )
end

App(; title="BonitoWidgets demo") do
    # Full VSCode-style workspace: Editor/Plot/Log all start in one tab
    # group. DRAG a tab to an edge of the body and only that panel splits
    # out — the remaining tabs stay together (| tabs(Editor, Plot) | Log |).
    # Keep dragging to build | Editor | Plot | Log |, drop tabs onto another
    # group's strip or center to merge them back into tabs (empty groups
    # dissolve automatically). Gutters between groups drag-resize. The
    # arrangement lives in ws.layout (plain JSON-able data) for save/restore.
    ws = Workspace(
        "Editor" => placeholder("Editor", "#3b82f6"),
        "Plot" => placeholder("Plot", "#8b5cf6"),
        "Log" => placeholder("Log", "#10b981"),
    )

    # Flat panel group: the lightweight variant — all panels tabbed OR all
    # side by side, switched via the bar widgets or by dragging a tab into
    # the body (edges → split everything, center → tabs again).
    group = PanelGroup(
        "Scene" => placeholder("Scene", "#0ea5e9"),
        "Spectrum" => placeholder("Spectrum", "#dc2626"),
        "Timeline" => placeholder("Timeline", "#64748b");
        mode=:tabs,
    )

    # Two-pane split with headers + per-pane collapse, orientation
    # toggled from outside via its observable.
    split = SplitContainer(
        placeholder("A", "#f59e0b"), placeholder("B", "#ef4444");
        titles=("Pane A", "Pane B"), split=0.4,
    )

    # Plain tabs: lightweight, no docking — but closable.
    tabs = Tabs(
        "First" => placeholder("First tab", "#0ea5e9"),
        "Second" => placeholder("Second tab", "#64748b"),
        "Third" => placeholder("Third tab", "#dc2626");
        closable=true,
    )

    coll = Collapsible("Collapsible section", placeholder("Hidden content", "#475569"))

    float = FloatingWindow(placeholder("Floating!", "#7c3aed");
                           title="Floating window", x=720, y=420, width=320, height=200)

    DOM.div(
        Theme(),
        caption("Workspace — drag a tab to an edge to split it out (others stay tabbed), to a strip/center to merge back:"),
        DOM.div(ws; style=Styles("height" => "300px")),
        caption("PanelGroup (flat) — edge drop splits all panels side by side, center drop re-tabs them:"),
        DOM.div(group; style=Styles("height" => "220px")),
        caption("SplitContainer + OrientationToggle:", OrientationToggle(split.direction)),
        DOM.div(split; style=Styles("height" => "200px")),
        caption("Tabs (closable, no docking):"),
        DOM.div(tabs; style=Styles("height" => "160px")),
        coll,
        float;
        style=Styles(
            "display" => "flex", "flex-direction" => "column", "gap" => "10px",
            "padding" => "16px", "background" => "var(--bw-bg)",
            "min-height" => "100dvh", "box-sizing" => "border-box",
        ),
    )
end
