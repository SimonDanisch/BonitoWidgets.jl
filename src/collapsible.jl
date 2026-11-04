const COLLAPSIBLE_LIB = Bonito.ES6Module(joinpath(@__DIR__, "..", "assets", "collapsible.js"))

"""
    Collapsible(header, content; expanded=true, states=String[], state=first(states),
                class="bw-collapsible", header_class="bw-collapsible-header", attributes...)

A section that folds its content away, on a native `<details>`. `header` (any
renderable) is always visible, and clicking it toggles the content. The content
stays mounted while collapsed, so widget state and WebGL contexts survive.

`content` can be a function returning the content. It's called the first time the
section is open, so a section nobody opens costs almost nothing, and what it returned
stays mounted from then on.

A click on a control in the header (a button, link or input), or one whose handler
called `preventDefault`, doesn't toggle.

`expanded::Observable{Bool}` is bidirectional: clicks notify Julia, and setting it
from Julia opens or closes the section.

`states` lists open states a click cycles through before closing, such as
`["summary", "full"]`, with the current one in `data-state` for CSS to size the content.

`class` and `header_class` replace the default look, so a section restyled from CSS
doesn't have to undo it. Other attributes, such as `style`, go on the `<details>`.
"""
struct Collapsible
    header::Any
    content::Any
    expanded::Observable{Bool}
    states::Vector{String}
    state::Union{Nothing,String}
    class::String
    header_class::String
    attributes::Dict{Symbol,Any}
end

function Collapsible(header, content; expanded::Union{Bool,Observable{Bool}}=true,
                     states::AbstractVector{<:AbstractString}=String[],
                     state::Union{Nothing,AbstractString}=isempty(states) ? nothing : first(states),
                     class::AbstractString="bw-collapsible",
                     header_class::AbstractString="bw-collapsible-header", attributes...)
    expanded_obs = expanded isa Observable ? expanded : Observable(expanded)
    return Collapsible(header, content, expanded_obs, collect(String, states), state,
                       class, header_class, Dict{Symbol,Any}(attributes))
end

mounted_content(::Session, content, ::Observable{Bool}) = content

function mounted_content(session::Session, build::Function, expanded::Observable{Bool})
    expanded[] && return build()
    placeholder = DOM.div()
    # Set before the render, which writes it into the page for the swap to find.
    id = Bonito.uuid(session, placeholder)
    built = Threads.Atomic{Bool}(false)
    on(session, expanded) do open
        if open && !Threads.atomic_xchg!(built, true)
            content = build()
            lock(Bonito.deletion_lock(Bonito.root_session(session))) do
                Bonito.isclosed(session) || Bonito.update_session_dom!(session, id, content; replace=true)
            end
        end
        return
    end
    return placeholder
end

function Bonito.jsrender(session::Session, c::Collapsible)
    summary = DOM.summary(c.header; class=c.header_class)
    wire = js"$(COLLAPSIBLE_LIB).then(lib => lib.connect($(summary), $(c.expanded), $(c.states)))"
    attributes = copy(c.attributes)
    isnothing(c.state) || (attributes[:dataState] = c.state)
    default_look = c.class == "bw-collapsible" ? (THEME_STYLES, COLLAPSIBLE_STYLES) : ()
    return Bonito.jsrender(session, DOM.details(default_look..., summary,
        mounted_content(session, c.content, c.expanded), wire;
        class=c.class, open=c.expanded[], attributes...))
end

# A `::before` glyph swapped on `[open]`, not a rotated icon: one CSS rule instead of
# an SVG per section. Browsers with `::details-content` animate the fold, others just open.
const COLLAPSIBLE_STYLES = Styles(
    CSS(".bw-collapsible",
        "background-color" => "var(--bw-bg-panel)",
        "border" => "1px solid var(--bw-border)",
        "border-radius" => "var(--bw-radius)",
        "box-sizing" => "border-box",
        "overflow" => "hidden",
        "interpolate-size" => "allow-keywords",
    ),
    CSS(".bw-collapsible::details-content",
        "block-size" => "0",
        "overflow" => "clip",
        "transition" => "block-size var(--bw-transition), content-visibility var(--bw-transition) allow-discrete",
    ),
    CSS(".bw-collapsible[open]::details-content", "block-size" => "auto"),
    CSS(".bw-collapsible-header",
        "display" => "flex",
        "align-items" => "center",
        "gap" => "var(--bw-space-2)",
        "padding" => "var(--bw-space-2) var(--bw-space-3)",
        "min-height" => "calc(var(--bw-bar-size) * 0.8)",
        "box-sizing" => "border-box",
        "background-color" => "var(--bw-bg-bar)",
        "color" => "var(--bw-text)",
        "font-family" => "var(--bw-font)",
        "font-size" => "var(--bw-font-size)",
        "cursor" => "pointer",
        "list-style" => "none",
        "user-select" => "none",
        "-webkit-tap-highlight-color" => "transparent",
        "transition" => "background-color var(--bw-transition)",
    ),
    CSS(".bw-collapsible-header::-webkit-details-marker", "display" => "none"),
    CSS(".bw-collapsible-header::before",
        "content" => "\"▸\"",
        "color" => "var(--bw-text-muted)",
        "flex-shrink" => "0",
    ),
    CSS(".bw-collapsible[open] > .bw-collapsible-header::before", "content" => "\"▾\""),
    CSS(".bw-collapsible-header:hover", "background-color" => "var(--bw-bg-hover)"),
    CSS(".bw-collapsible[open] > .bw-collapsible-header",
        "border-bottom" => "1px solid var(--bw-border)"),
)
