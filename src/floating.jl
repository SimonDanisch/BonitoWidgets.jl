"""
    FloatingWindow(body; title="", x=80, y=80, width=640, height=420,
                   visible=true, close_trigger=Observable(false), style=Styles())

A draggable, resizable, fixed-position window: drag the title bar to move,
drag the SE corner to resize, both clamped to the viewport. Works with mouse
and touch (pointer events).

Geometry (`x`, `y`, `width`, `height`), `visible`, and `close_trigger` are
Observables, so callers can persist gestures and push updates the other way
(e.g. restore saved geometry). The close button only notifies
`close_trigger` — the caller decides what closing means (hide, park, …):

```julia
w = FloatingWindow(content; title="Tools")
on(w.close_trigger) do _
    w.visible[] = false
end
```
"""
struct FloatingWindow
    body::Any
    title::Any
    x::Observable{Int}
    y::Observable{Int}
    width::Observable{Int}
    height::Observable{Int}
    visible::Observable{Bool}
    close_trigger::Observable{Bool}
    style::Styles
end

function FloatingWindow(body;
                        title="",
                        x::Union{Int,Observable{Int}}=80,
                        y::Union{Int,Observable{Int}}=80,
                        width::Union{Int,Observable{Int}}=640,
                        height::Union{Int,Observable{Int}}=420,
                        visible::Union{Bool,Observable{Bool}}=true,
                        close_trigger::Observable{Bool}=Observable(false),
                        style=Styles())
    asobs(v::Observable) = v
    asobs(v) = Observable(v)
    return FloatingWindow(body, title,
                          asobs(x), asobs(y), asobs(width), asobs(height),
                          asobs(visible), close_trigger, style)
end

function Bonito.jsrender(session::Session, w::FloatingWindow)
    title_bar = DOM.div(
        DOM.span(w.title; class="bw-float-title-text"),
        DOM.button(icon_close(); class="bw-icon-btn bw-float-close", title="Close");
        class="bw-float-title",
    )
    container = DOM.div(
        title_bar,
        DOM.div(w.body; class="bw-float-body"),
        DOM.div(""; class="bw-float-resize", title="Drag to resize");
        class="bw-float",
        # Initial inline geometry so the first paint is right even before the
        # setup script runs.
        style=Styles(w.style,
            "left" => string(w.x[], "px"),
            "top" => string(w.y[], "px"),
            "width" => string(w.width[], "px"),
            "height" => string(w.height[], "px"),
            "display" => w.visible[] ? "flex" : "none",
        ),
    )

    # Math.round on notify: pointer values are floats under subpixel layout
    # and the observables are Int — without rounding every drag end would
    # throw InexactError.
    setup = js"""
    (() => {
        const el = $(container);
        const titleBar = el.querySelector('.bw-float-title');
        const handle = el.querySelector('.bw-float-resize');
        const closeBtn = el.querySelector('.bw-float-close');

        const xObs = $(w.x), yObs = $(w.y);
        const wObs = $(w.width), hObs = $(w.height);
        const visObs = $(w.visible), closeObs = $(w.close_trigger);

        const MIN_W = 200, MIN_H = 120;
        const clampX = (x) => Math.max(0, Math.min(window.innerWidth - 48, x));
        const clampY = (y) => Math.max(0, Math.min(window.innerHeight - 32, y));

        const applyGeom = () => {
            el.style.left = clampX(xObs.value) + 'px';
            el.style.top = clampY(yObs.value) + 'px';
            el.style.width = wObs.value + 'px';
            el.style.height = hObs.value + 'px';
        };
        const applyVis = () => { el.style.display = visObs.value ? 'flex' : 'none'; };
        xObs.on(applyGeom); yObs.on(applyGeom);
        wObs.on(applyGeom); hObs.on(applyGeom);
        visObs.on(applyVis);
        applyGeom(); applyVis();

        titleBar.addEventListener('pointerdown', (ev) => {
            if (ev.target.closest('.bw-float-close')) return;
            const offX = ev.clientX - el.offsetLeft;
            const offY = ev.clientY - el.offsetTop;
            let lastX = el.offsetLeft, lastY = el.offsetTop;
            const onMove = (e2) => {
                lastX = clampX(e2.clientX - offX);
                lastY = clampY(e2.clientY - offY);
                el.style.left = lastX + 'px';
                el.style.top = lastY + 'px';
            };
            const onUp = () => {
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
                xObs.notify(Math.round(lastX)); yObs.notify(Math.round(lastY));
            };
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
            ev.preventDefault();
        });

        handle.addEventListener('pointerdown', (ev) => {
            const startW = el.offsetWidth, startH = el.offsetHeight;
            const startX = ev.clientX, startY = ev.clientY;
            let lastW = startW, lastH = startH;
            const onMove = (e2) => {
                lastW = Math.max(MIN_W, Math.min(window.innerWidth, startW + (e2.clientX - startX)));
                lastH = Math.max(MIN_H, Math.min(window.innerHeight, startH + (e2.clientY - startY)));
                el.style.width = lastW + 'px';
                el.style.height = lastH + 'px';
            };
            const onUp = () => {
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
                wObs.notify(Math.round(lastW)); hObs.notify(Math.round(lastH));
            };
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
            ev.preventDefault(); ev.stopPropagation();
        });

        closeBtn.addEventListener('click', (ev) => {
            ev.stopPropagation();
            closeObs.notify(true);
        });
    })();
    """

    return Bonito.jsrender(session, DOM.div(
        THEME_STYLES, ICON_BUTTON_STYLES, FLOATING_STYLES,
        container, DOM.script(setup);
        style=Styles("display" => "contents"),
    ))
end

const FLOATING_STYLES = Styles(
    CSS(".bw-float",
        "position" => "fixed",
        "z-index" => "var(--bw-z-float)",
        "background-color" => "var(--bw-bg-panel)",
        "color" => "var(--bw-text)",
        "font-family" => "var(--bw-font)",
        "font-size" => "var(--bw-font-size)",
        "border" => "1px solid var(--bw-border)",
        "border-radius" => "var(--bw-radius)",
        "box-shadow" => "var(--bw-shadow)",
        "display" => "flex",
        "flex-direction" => "column",
        "overflow" => "hidden",
        "min-width" => "200px",
        "min-height" => "120px",
        "box-sizing" => "border-box",
    ),
    CSS(".bw-float-title",
        "display" => "flex",
        "align-items" => "center",
        "gap" => "var(--bw-space-2)",
        "padding" => "var(--bw-space-1) var(--bw-space-2)",
        "min-height" => "calc(var(--bw-bar-size) * 0.9)",
        "box-sizing" => "border-box",
        "background-color" => "var(--bw-bg-bar)",
        "border-bottom" => "1px solid var(--bw-border)",
        "cursor" => "move",
        "touch-action" => "none",
        "user-select" => "none",
        "flex-shrink" => "0",
    ),
    CSS(".bw-float-title-text",
        "flex" => "1 1 auto",
        "min-width" => "0",
        "overflow" => "hidden",
        "text-overflow" => "ellipsis",
        "white-space" => "nowrap",
        "font-size" => "var(--bw-font-size-sm)",
        "font-weight" => "600",
    ),
    CSS(".bw-float-body",
        "flex" => "1 1 auto",
        "overflow" => "auto",
        "position" => "relative",
        "min-height" => "0",
        "-webkit-overflow-scrolling" => "touch",
    ),
    # SE-corner resize handle: pure-CSS chevron, larger hit area on touch.
    CSS(".bw-float-resize",
        "position" => "absolute",
        "right" => "0", "bottom" => "0",
        "width" => "calc(var(--bw-gutter-size) + 6px)",
        "height" => "calc(var(--bw-gutter-size) + 6px)",
        "cursor" => "nwse-resize",
        "touch-action" => "none",
        "background" =>
            "linear-gradient(135deg, transparent 50%, var(--bw-border) 50%, var(--bw-border) 60%, " *
            "transparent 60%, transparent 70%, var(--bw-border) 70%, var(--bw-border) 80%, transparent 80%)",
    ),
)
