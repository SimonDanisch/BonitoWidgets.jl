# Popover menus and modal dialogs: the two overlays a page dismisses with a
# click outside or Escape. Each keeps its open state in an `Observable{Bool}`,
# so Julia can open and close it and react to it, and the browser side
# (`assets/overlays.js`) follows that observable.

const OVERLAYS_LIB = Bonito.ES6Module(joinpath(@__DIR__, "..", "assets", "overlays.js"))

# A class attribute: `base` plus `extra`, which may change over time.
join_class(::Session, base::String, extra::AbstractString) =
    isempty(extra) ? base : string(base, " ", extra)
join_class(session::Session, base::String, extra::Observable{String}) =
    map(e -> join_class(session, base, e), session, extra)

"""
    Menu(items; label="⋯", title="More actions", class="",
         trigger_class="bw-btn-secondary bw-btn-sm", close_on_pick=true,
         open=Observable(false))

A button that opens `items` in a popover below it. Clicking outside or pressing
Escape closes it, and so does clicking an element with class `bw-menu-item`,
unless `close_on_pick=false` (a list of checkboxes, say).

`items` is any renderable, usually a vector of `bw-menu-item` buttons, with
`bw-menu-title` headings and `bw-menu-sep` separators in between. `class` adds
classes to the menu, `trigger_class` to its button; either may be an
`Observable{String}`. `open` is the state: set it to open or close the menu from
Julia, or listen to it.

```julia
Menu([DOM.button("Rename"; class = "bw-menu-item", onclick = js"..."),
      DOM.div(; class = "bw-menu-sep"),
      DOM.button("Delete"; class = "bw-menu-item bw-menu-danger", onclick = js"...")])
```
"""
struct Menu
    items::Any
    label::Any
    title::String
    class::Union{String,Observable{String}}
    trigger_class::Union{String,Observable{String}}
    close_on_pick::Bool
    open::Observable{Bool}
end

function Menu(items; label = "⋯", title::AbstractString = "More actions",
              class::Union{AbstractString,Observable{String}} = "",
              trigger_class::Union{AbstractString,Observable{String}} = "bw-btn-secondary bw-btn-sm",
              close_on_pick::Bool = true, open::Observable{Bool} = Observable(false))
    return Menu(items, label, String(title), as_class(class), as_class(trigger_class),
                close_on_pick, open)
end

as_class(c::AbstractString) = String(c)
as_class(c::Observable{String}) = c

function Bonito.jsrender(session::Session, m::Menu)
    trigger = DOM.button(m.label; type = "button", title = m.title,
                         class = join_class(session, "bw-btn bw-menu-trigger", m.trigger_class))
    list = DOM.div(m.items; class = "bw-menu-list")
    # The menu itself is the trigger's parent: a script can't name the node it
    # sits in.
    wire = js"""$(OVERLAYS_LIB).then(lib => new lib.Menu($(trigger).parentElement, $(trigger),
        $(list), $(m.open), $(m.close_on_pick)))"""
    root = DOM.div(THEME_STYLES, BUTTON_STYLES, MENU_STYLES, trigger, list, wire;
                   class = join_class(session, "bw-menu", m.class))
    return Bonito.jsrender(session, root)
end

const MENU_STYLES = Styles(
    CSS(".bw-menu", "position" => "relative", "display" => "inline-flex"),
    # Block layout inside the list on purpose: items rendered from an Observable
    # arrive inside Bonito's wrapper node, and block children lay out the same
    # with or without that wrapper.
    CSS(".bw-menu-list",
        "display" => "none",
        "position" => "absolute", "top" => "calc(100% + 4px)", "right" => "0",
        "min-width" => "220px",
        "background" => "var(--bw-bg-panel)",
        "border" => "1px solid var(--bw-border-strong)",
        "border-radius" => "var(--bw-radius)",
        "box-shadow" => "var(--bw-shadow-md)",
        "padding" => "4px",
        "z-index" => "60",
        "text-align" => "left"),
    CSS(".bw-menu-open > .bw-menu-list", "display" => "block"),
    CSS(".bw-menu-title",
        "font-size" => "var(--bw-font-size-xs)", "font-weight" => "600",
        "letter-spacing" => "0.06em", "text-transform" => "uppercase",
        "color" => "var(--bw-text-muted)",
        "padding" => "6px 10px 2px"),
    # A button or a link: `text-decoration` is for the link.
    CSS(".bw-menu-item",
        "appearance" => "none", "border" => "0", "background" => "transparent",
        "display" => "block", "width" => "100%", "box-sizing" => "border-box",
        "text-align" => "left", "font" => "inherit", "font-size" => "var(--bw-font-size-ui)",
        "line-height" => "18px", "text-decoration" => "none",
        "color" => "var(--bw-text)",
        "padding" => "6px 10px",
        "border-radius" => "var(--bw-radius-sm)",
        "cursor" => "pointer", "white-space" => "nowrap"),
    CSS(".bw-menu-item:hover", "background" => "var(--bw-bg-subtle)"),
    CSS(".bw-menu-sep",
        "height" => "1px", "background" => "var(--bw-border)", "margin" => "4px 6px"),
    CSS(".bw-menu-danger", "color" => "var(--bw-error)"),
    CSS(".bw-menu-danger:hover",
        "background" => "color-mix(in srgb, var(--bw-error) 10%, transparent)"),
)

"""
    Modal(content::Function, open::Observable{Bool}; title="")

A dialog over the page while `open[]` is true, closed by its ✕, a click on the
backdrop or Escape. `content()` builds the body anew on every open, so a form
starts out empty each time.

```julia
adding = Observable(false)
DOM.div(
    DOM.button("Add…"; class = "bw-btn", onclick = js"e => \$(adding).notify(true)"),
    Modal(adding; title = "Add account") do
        account_form()
    end)
```
"""
struct Modal
    content::Function
    open::Observable{Bool}
    title::String
end

Modal(content::Function, open::Observable{Bool}; title::AbstractString = "") =
    Modal(content, open, String(title))

function Bonito.jsrender(session::Session, m::Modal)
    close = DOM.button("✕"; type = "button", title = "Close",
                       class = "bw-btn bw-btn-ghost bw-btn-sm bw-modal-close")
    body = map(session, m.open) do open
        DOM.div(open ? m.content() : nothing; class = "bw-modal-body")
    end
    card = DOM.div(DOM.div(DOM.span(m.title; class = "bw-modal-title"), close;
                           class = "bw-modal-head"),
                   body;
                   class = "bw-modal-card", role = "dialog", var"aria-modal" = "true")
    # The overlay is the card's parent: a script can't name the node it sits in.
    wire = js"""$(OVERLAYS_LIB).then(lib => new lib.Modal($(card).parentElement, $(close), $(m.open)))"""
    overlay = DOM.div(THEME_STYLES, BUTTON_STYLES, MODAL_STYLES, card, wire;
                      class = "bw-modal-overlay")
    return Bonito.jsrender(session, overlay)
end

const MODAL_STYLES = Styles(
    # Fixed, so the dialog appears where the user looks, even when the control
    # that opened it is scrolled far away. The card scrolls inside rather than
    # growing past the viewport.
    CSS(".bw-modal-overlay",
        "position" => "fixed", "inset" => "0",
        "background" => "var(--bw-backdrop)",
        "z-index" => "calc(var(--bw-z-float) + 1)",
        "display" => "none", "align-items" => "center", "justify-content" => "center",
        "padding" => "var(--bw-space-4)"),
    CSS(".bw-modal-overlay.bw-modal-open", "display" => "flex"),
    CSS(".bw-modal-card",
        "background" => "var(--bw-bg-panel)",
        "border" => "1px solid var(--bw-border-strong)",
        "border-radius" => "var(--bw-radius)",
        "box-shadow" => "var(--bw-shadow-md)",
        "width" => "min(560px, 100%)",
        "max-height" => "85vh", "overflow-y" => "auto",
        "display" => "flex", "flex-direction" => "column"),
    CSS(".bw-modal-head",
        "display" => "flex", "align-items" => "center", "justify-content" => "space-between",
        "gap" => "var(--bw-space-3)",
        "padding" => "14px 16px",
        "border-bottom" => "1px solid var(--bw-border)"),
    CSS(".bw-modal-title", "font-weight" => "600", "font-size" => "var(--bw-font-size)"),
    CSS(".bw-modal-body", "padding" => "4px 16px 16px"),
)
