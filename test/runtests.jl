using Test
using Bonito
using BonitoWidgets
using BonitoWidgets: string_bridge

# Render any component offline and return the HTML string.
function render_html(component)
    app = App(() -> DOM.div(component))
    session = Session(Bonito.NoConnection(); asset_server=Bonito.NoServer())
    dom = Bonito.session_dom(session, app)
    return sprint(io -> show(io, MIME"text/html"(), dom))
end

@testset "BonitoWidgets" begin
    @testset "string_bridge" begin
        dir = Observable(:row)
        s = string_bridge(dir)
        @test s[] == "row"
        dir[] = :column
        @test s[] == "column"
        s[] = "row"  # simulates a JS notify
        @test dir[] == :row
    end

    @testset "Tabs" begin
        t = Tabs("A" => DOM.div("a"), "B" => DOM.div("b"); active=2, closable=true)
        @test t.active[] == 2
        @test t.closed[] == 0
        html = render_html(t)
        @test occursin("bw-tabs", html)
        @test occursin("bw-tab-close", html)
        @test_throws ArgumentError Tabs(Pair{String,Any}[])
        @test_throws ArgumentError Tabs("A" => 1; active=2)
    end

    @testset "SplitContainer" begin
        sc = SplitContainer(DOM.div("a"), DOM.div("b"); direction=:horizontal, split=0.3)
        @test sc.direction[] == :row
        @test sc.split[] == 0.3
        @test sc.collapsed[] == 0
        sc2 = SplitContainer(1, 2; direction=:vertical)
        @test sc2.direction[] == :column
        @test_throws ArgumentError SplitContainer(1, 2; direction=:diagonal)

        # Bare panes by default, headers with titles. Match the class
        # *attribute* — the (always-included) stylesheet and JS contain the
        # class names as selector strings regardless.
        @test !occursin("class=\"bw-split-header\"", render_html(SplitContainer(1, 2)))
        html = render_html(SplitContainer(1, 2; titles=("A", "B")))
        @test occursin("class=\"bw-split-header\"", html)
        @test occursin("class=\"bw-split-collapse\"", html)

        # External observables are adopted, not copied
        dir = Observable(:row)
        sc3 = SplitContainer(1, 2; direction=dir)
        @test sc3.direction === dir
    end

    @testset "PanelGroup" begin
        g = PanelGroup("A" => 1, "B" => 2, "C" => 3; mode=:horizontal)
        @test g.mode[] == :row
        @test g.active[] == 1
        @test g.order[] == [1, 2, 3]
        @test g.fractions[] ≈ fill(1 / 3, 3)
        @test g.draggable
        @test_throws ArgumentError PanelGroup(Pair{String,Any}[])
        @test_throws ArgumentError PanelGroup("A" => 1; active=5)
        html = render_html(g)
        @test occursin("class=\"bw-group ", html)  # root carries a generated style_N class too
        @test occursin("class=\"bw-icon-btn bw-group-mode bw-active\"", html)
        # n-1 gutters
        @test count("class=\"bw-group-gutter bw-split-gutter", html) == 2
        @test occursin("class=\"bw-drop-overlay", html)
        # No chrome when disabled
        plain = render_html(PanelGroup("A" => 1, "B" => 2; mode_buttons=false, collapsible=false))
        @test !occursin("bw-icon-btn bw-group-mode", plain)
        @test !occursin("bw-icon-btn bw-group-collapse", plain)
    end

    @testset "Workspace" begin
        ws = Workspace("A" => DOM.div("a"), "B" => DOM.div("b"), "C" => DOM.div("c"))
        @test ws.layout[] == Dict("type" => "tabs", "panels" => [1, 2, 3], "active" => 1)
        @test ws.labels == ["A", "B", "C"]
        @test_throws ArgumentError Workspace(Pair{String,Any}[])

        # Layout builders
        @test tabgroup(2, 3) == Dict("type" => "tabs", "panels" => [2, 3], "active" => 2)
        @test tabgroup(2, 3; active=3)["active"] == 3
        @test_throws ArgumentError tabgroup(1, 2; active=5)
        lt = hsplit(tabgroup(1, 2), tabgroup(3); fractions=[0.7, 0.3])
        @test lt["type"] == "row" && lt["fractions"] == [0.7, 0.3]
        @test vsplit(tabgroup(1), tabgroup(2))["type"] == "column"
        @test_throws ArgumentError hsplit(tabgroup(1))
        @test_throws ArgumentError hsplit(tabgroup(1), tabgroup(2); fractions=[1.0])

        ws2 = Workspace("A" => 1, "B" => 2, "C" => 3; layout=lt)
        @test ws2.layout[] === lt
        html = render_html(ws2)
        @test occursin("class=\"bw-ws ", html)
        @test occursin("class=\"bw-ws-parking", html)
        @test count("class=\"bw-ws-panel", html) == 3
    end

    @testset "Collapsible" begin
        c = Collapsible("Title", DOM.div("content"); expanded=false)
        @test !c.expanded[]
        html = render_html(c)
        @test occursin("bw-collapsible", html)
        @test occursin("0fr", html)
    end

    @testset "FloatingWindow" begin
        w = FloatingWindow(DOM.div("body"); title="T", x=10, y=20, width=300, height=200)
        @test w.x[] == 10 && w.y[] == 20
        @test w.visible[]
        html = render_html(w)
        @test occursin("bw-float", html)
        @test occursin("left: 10px", html)
    end

    @testset "Theme" begin
        @test Theme() isa Bonito.Styles
        th = render_html(DOM.div(Theme(scheme=:dark, accent="#00d4ff", bg_panel="black")))
        @test occursin(":root:root", th)
        @test occursin("--bw-accent: #00d4ff", th)
        @test occursin("--bw-bg-panel: black", th)
        @test_throws ArgumentError Theme(scheme=:blue)
        # Defaults carry the responsive bits
        base = render_html(DOM.div(Theme()))
        @test occursin("prefers-color-scheme: dark", base)
        @test occursin("pointer: coarse", base)
    end

    @testset "Widget buttons" begin
        dir = Observable(:row)
        @test occursin("bw-orient-toggle", render_html(OrientationToggle(dir)))
        collapsed = Observable(false)
        @test occursin("bw-collapse-btn", render_html(CollapseButton(collapsed)))
        @test occursin("bw-icon-btn", render_html(IconButton(DOM.span("x"); title="t")))
    end
end
