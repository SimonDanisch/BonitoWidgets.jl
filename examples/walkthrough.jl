# BonitoWidgets walkthrough, recorded with ElectronCall.Testing.
#
# A tour of the Workspace: steer plots, split the layout by dragging a tab to an
# edge, float a panel and dock it back. Every gesture is a real pointer event
# from ElectronCall's animated cursor, captured by its frame-pump recorder at
# 30 fps.
#
# No coordinates are hard-coded. The drag and click targets are the BonitoWidgets
# probes (tab, groupbody, floattitle) wrapped in ElectronCall's JS target; they
# resolve against the live DOM at play time, so the script keeps working as the
# layout moves around.
#
# Run:  julia --project=. dev/BonitoWidgets/examples/walkthrough.jl
# Out:  dev/BonitoWidgets/examples/walkthrough.mp4

using Bonito
using Bonito: Slider, Dropdown, Styles, CSS, DOM, Observable
using BonitoWidgets
using BonitoWidgets: tab, groupbody, floattitle
import WGLMakie as WM
using WGLMakie: Figure, Axis, Axis3, lines!, heatmap!, surface!, hidedecorations!,
    hidespines!, limits!, Point2f, RGBf
using ElectronCall
using ElectronCall.Testing

WM.activate!()

# ── palette (matches BonitoWidgets dark theme) ──────────────────────────────
const BG    = RGBf(0.105, 0.115, 0.145)
const PANEL = RGBf(0.130, 0.140, 0.170)
const GRID  = RGBf(0.22, 0.23, 0.27)
const TXT   = RGBf(0.78, 0.80, 0.85)
const MUT   = RGBf(0.55, 0.57, 0.63)

styled_axis(fig, pos; kw...) = Axis(fig[pos...];
    backgroundcolor=PANEL, titlecolor=TXT, titlesize=18,
    xlabelcolor=MUT, ylabelcolor=MUT, xticklabelcolor=MUT, yticklabelcolor=MUT,
    xgridcolor=GRID, ygridcolor=GRID, xtickcolor=GRID, ytickcolor=GRID,
    leftspinecolor=GRID, rightspinecolor=GRID, topspinecolor=GRID, bottomspinecolor=GRID,
    kw...)

# ── the app ─────────────────────────────────────────────────────────────────
function build_app()
    App(; title="BonitoWidgets · Signal Lab") do session
        a_sl     = Slider(1:1:7; value=3)
        b_sl     = Slider(1:1:7; value=2)
        delta_sl = Slider(0:0.05:Float64(2pi); value=Float64(pi)/2)
        harm_sl  = Slider(1:1:12; value=5)
        freqf_sl = Slider(0.5:0.1:4.0; value=1.8)
        rot_sl   = Slider(0.0:0.05:Float64(2pi); value=0.6)
        amp_sl   = Slider(0.2:0.05:1.6; value=1.0)
        cmap_dd  = Dropdown(["viridis","plasma","magma","inferno","turbo"]; index=2)
        cmap = map(Symbol, cmap_dd.value)

        # Phase portrait: a Lissajous curve coloured along its path.
        tt = range(0, 2pi, length=2400)
        liss = map(a_sl.value, b_sl.value, delta_sl.value) do a, b, d
            Point2f.(sin.(a .* tt .+ d), sin.(b .* tt))
        end
        figL = Figure(size=(620, 460), backgroundcolor=BG)
        axL = styled_axis(figL, (1,1); title="Phase Portrait", aspect=1)
        hidedecorations!(axL); hidespines!(axL)
        lines!(axL, liss; color=collect(tt), colormap=cmap, linewidth=2.8)
        limits!(axL, -1.15, 1.15, -1.15, 1.15)

        # Waveform: partial Fourier square wave.
        xs = range(0, 2pi, length=600)
        wave = map(harm_sl.value, amp_sl.value, freqf_sl.value) do n, amp, f
            [amp * sum(sin((2k-1) * f * x) / (2k-1) for k in 1:n) for x in xs]
        end
        figW = Figure(size=(620, 380), backgroundcolor=BG)
        axW = styled_axis(figW, (1,1); title="Waveform", xlabel="t", ylabel="amplitude")
        lines!(axW, collect(xs), wave; color=:cyan, linewidth=2.8)

        # Field: rotating interference heatmap.
        rr = range(-3, 3, length=140)
        field = map(rot_sl.value, freqf_sl.value) do θ, f
            [sin(f*(x*cos(θ) - y*sin(θ))) * cos(f*(x*sin(θ) + y*cos(θ))) for x in rr, y in rr]
        end
        figF = Figure(size=(560, 460), backgroundcolor=BG)
        axF = styled_axis(figF, (1,1); title="Interference Field", aspect=1)
        hidedecorations!(axF)
        heatmap!(axF, rr, rr, field; colormap=cmap, interpolate=true)

        # Surface inspector (starts floating).
        sr = range(-3, 3, length=70)
        surfz = map(rot_sl.value, amp_sl.value) do θ, amp
            [amp * sin(sqrt(x^2+y^2)*2 - θ*3) / (0.5 + sqrt(x^2+y^2)) for x in sr, y in sr]
        end
        figS = Figure(size=(380, 320), backgroundcolor=BG)
        axS = Axis3(figS[1,1]; backgroundcolor=PANEL, title="Surface", titlecolor=TXT,
            xgridcolor=GRID, ygridcolor=GRID, zgridcolor=GRID,
            xticklabelcolor=MUT, yticklabelcolor=MUT, zticklabelcolor=MUT)
        surface!(axS, sr, sr, surfz; colormap=cmap)

        section(t) = DOM.div(t; style=Styles("font-weight"=>"600","font-size"=>"12px",
            "letter-spacing"=>"0.04em","text-transform"=>"uppercase","color"=>"#7f8694","margin"=>"14px 0 6px"))
        row(lbl, w) = DOM.div(
            DOM.div(lbl; style=Styles("font-size"=>"12px","color"=>"#aab","margin-bottom"=>"2px")),
            DOM.div(w; style=Styles("width"=>"100%"));
            style=Styles("margin"=>"7px 0"))
        controls = DOM.div(
            DOM.div("Signal Lab"; style=Styles("font-size"=>"17px","font-weight"=>"700","color"=>"#e6e8ee")),
            section("Phase Portrait"),
            row("X frequency", a_sl), row("Y frequency", b_sl), row("Phase δ", delta_sl),
            section("Waveform"),
            row("Harmonics", harm_sl), row("Base frequency", freqf_sl), row("Amplitude", amp_sl),
            section("Field & Surface"),
            row("Rotation", rot_sl), row("Colormap", cmap_dd);
            style=Styles("padding"=>"14px 16px","height"=>"100%","overflow-y"=>"auto","box-sizing"=>"border-box"))
        plotwrap(fig) = DOM.div(fig; style=Styles("width"=>"100%","height"=>"100%",
            "display"=>"flex","align-items"=>"center","justify-content"=>"center","padding"=>"6px"))

        ws = Workspace(
            Panel("controls", controls; label="Controls", closable=false),
            Panel("phase",    plotwrap(figL); label="Phase Portrait", closable=true),
            Panel("wave",     plotwrap(figW); label="Waveform", closable=true),
            Panel("field",    plotwrap(figF); label="Field", closable=true),
            Panel("surface",  plotwrap(figS); label="Surface", closable=true);
            layout = workspacelayout(
                hsplit(tabgroup("controls"),
                       tabgroup("phase","wave","field"; active="phase"); fractions=[0.26,0.74]);
                floating=[floatpanel("surface"; x=830, y=40, width=380, height=330)]),
            style = Styles("--bw-bg-panel"=>"#1f242d"))

        header = DOM.div(
            DOM.div("BonitoWidgets"; style=Styles("font-weight"=>"700","color"=>"#e6e8ee","font-size"=>"15px")),
            DOM.div("Signal Lab: drag tabs, float panels, steer live plots";
                style=Styles("color"=>"#7f8694","font-size"=>"12.5px","margin-left"=>"10px"));
            style=Styles("display"=>"flex","align-items"=>"baseline","gap"=>"4px",
                "height"=>"46px","padding"=>"0 18px","flex"=>"0 0 auto","border-bottom"=>"1px solid #2a2f3a"))

        DOM.div(header,
            DOM.div(ws; style=Styles("flex"=>"1 1 0","margin"=>"10px","min-height"=>"0",
                "border"=>"1px solid #2a2f3a","border-radius"=>"8px","overflow"=>"hidden"));
            style=Styles("display"=>"flex","flex-direction"=>"column","height"=>"100dvh",
                "width"=>"100vw","background"=>"#15181e","box-sizing"=>"border-box"))
    end
end

# ── the recorded tour ─────────────────────────────────────────────────────────
# The whole tour as one event list, played in order.
function tour(ctx)
    play(ctx, [
        Wait(1.0),

        # 1 ─ widgets steer the plots
        MouseTo((90, 185)),
        Steer(0, 0.85; duration=1.1),          # X frequency
        Steer(1, 0.62; duration=1.0),          # Y frequency
        Steer(2, 0.95; duration=1.2),          # Phase δ
        Wait(0.3),
        Click(Sel("select")),                  # open the colormap dropdown
        SelectOption("select", 4),             # turbo
        Wait(0.8),
        Steer(2, 0.30; duration=1.1),          # sweep phase back
        Wait(0.4),

        # 2 ─ switch tab, steer the waveform
        Click(JS(tab("Waveform"))),
        Wait(0.5),
        Steer(3, 0.95; duration=1.1),          # harmonics → crisp square wave
        Steer(4, 0.65; duration=1.0),          # base frequency
        Wait(0.4),

        # 3 ─ switch tab, rotate the field
        Click(JS(tab("Field"))),
        Wait(0.5),
        Steer(6, 0.85; duration=1.4),          # rotation sweeps the field
        SelectOption("select", 1),             # plasma
        Wait(0.5),

        # 4 ─ drag the Field tab to the bottom edge → split the layout
        Drag(JS(tab("Field")),
             [JS(groupbody("Field"; rel=(0.5, 0.5))), JS(groupbody("Field"; rel=(0.5, 0.9)))];
             grab=0.4, move=0.9),
        Wait(1.2),

        # 5 ─ drag it back up into the tab strip → back to tabs
        Drag(JS(tab("Field")), JS(tab("Waveform")); grab=0.4, move=0.9),
        Wait(1.0),

        # 6 ─ dock the floating Surface onto the tab strip
        Drag(JS(floattitle("Surface")), JS(tab("Phase Portrait")); grab=0.4, move=1.0),
        Wait(1.0),

        # 7 ─ tear the Phase Portrait tab out into a floating window
        Drag(JS(tab("Phase Portrait")), (760, 18); grab=0.4, move=1.0),
        Wait(1.2),

        # 8 ─ drag the floating window back onto the dock
        Drag(JS(floattitle("Phase Portrait")), JS(tab("Waveform")); grab=0.4, move=1.0),
        Wait(1.0),
        MouseTo((640, 430)), Wait(1.0),
    ])
end

# ── run ──────────────────────────────────────────────────────────────────────
function run(; outpath=joinpath(@__DIR__, "walkthrough.mp4"))
    server = Bonito.Server(build_app(), "127.0.0.1", 8920)
    ctx = open_window("http://127.0.0.1:8920"; width=1280, height=860)
    try
        sleep(7)
        install_error_sink(ctx)
        set_window_size(ctx, 1280, 840)
        eval_js(ctx, "document.documentElement.style.overflow='hidden';document.body.style.margin='0';document.body.style.overflow='hidden'")
        wait_for(ctx, "document.querySelectorAll('canvas').length >= 4"; timeout=20.0)
        sleep(2)
        install_cursor(ctx; start=(150, 110))
        sleep(0.5)

        record_video(() -> tour(ctx), ctx, outpath; fps=30)

        errs = js_errors(ctx)
        isempty(errs) || @warn "JS errors during walkthrough" errs
        @info "wrote $outpath"
    finally
        close(ctx); close(server)
    end
    return outpath
end

run()
