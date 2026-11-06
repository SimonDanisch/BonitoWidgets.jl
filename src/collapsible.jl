const COLLAPSIBLE_LIB = Bonito.ES6Module(joinpath(@__DIR__, "..", "assets", "collapsible.js"))

"""
    Collapsible(header, content; expanded=true, states=String[], state=first(states),
                class="bw-collapsible", header_class="bw-collapsible-header", attributes...)

A section that folds its content away, on a native `<details>`. `header` (any
renderable) is always visible, and clicking it toggles the content. The content
stays mounted while collapsed, so widget state and WebGL contexts survive.

`content` can be a function returning the content. It's called the first time the
section is open, and what it returned stays mounted from then on. Showing many
sections, use a [`CollapsibleList`](@ref): they then share one script.

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
            # The click can still be on its way when the page closes.
            Bonito.isclosed(session) || Bonito.update_session_dom!(session, id, content; replace=true)
        end
        return
    end
    return placeholder
end

"""
    CollapsibleList(sections; attributes...)

Several [`Collapsible`](@ref)s rendered side by side with one script and one channel
to Julia for all of them, so a closed section costs about what a plain `<details>`
does. `attributes` go on the element holding the sections.
"""
struct CollapsibleList
    sections::Vector{Collapsible}
    attributes::Dict{Symbol,Any}
end

CollapsibleList(sections; attributes...) =
    CollapsibleList(collect(Collapsible, sections), Dict{Symbol,Any}(attributes))

default_look(c::Collapsible) = c.class == "bw-collapsible" ? (THEME_STYLES, COLLAPSIBLE_STYLES) : ()

# The section's summary, its `<details>` children and attributes, without any script.
function section_parts(session::Session, c::Collapsible, key::Int)
    summary = DOM.summary(c.header; class=c.header_class)
    attributes = merge(Dict{Symbol,Any}(:class => c.class, :open => c.expanded[], :dataBwKey => key), c.attributes)
    isnothing(c.state) || (attributes[:dataState] = c.state)
    isempty(c.states) || (attributes[:dataStates] = join(c.states, " "))
    return summary, mounted_content(session, c.content, c.expanded), attributes
end

# `shown` is what the browser shows, so a click doesn't come back to it as an update.
function section_wiring(session::Session, sections::Vector{Collapsible}, anchor)
    shown = Bool[c.expanded[] for c in sections]
    from_browser = Observable{Any}(nothing)
    to_browser = Observable{Any}(nothing)
    on(session, from_browser) do (key, open)
        if shown[key] != open
            shown[key] = open
            sections[key].expanded[] = open
        end
        return
    end
    for (key, c) in enumerate(sections)
        on(session, c.expanded) do open
            if shown[key] != open
                shown[key] = open
                to_browser[] = Any[key, open]
            end
            return
        end
    end
    return js"$(COLLAPSIBLE_LIB).then(lib => lib.connect($(anchor), $(from_browser), $(to_browser), $(findall(shown))))"
end

function Bonito.jsrender(session::Session, c::Collapsible)
    summary, content, attributes = section_parts(session, c, 1)
    return Bonito.jsrender(session, DOM.details(default_look(c)..., summary, content,
        section_wiring(session, [c], summary); dataBwSections="", attributes...))
end

function Bonito.jsrender(session::Session, list::CollapsibleList)
    sections = map(enumerate(list.sections)) do (key, c)
        summary, content, attributes = section_parts(session, c, key)
        return DOM.details(default_look(c)..., summary, content; attributes...)
    end
    root = DOM.div(sections; dataBwSections="", list.attributes...)
    return Bonito.jsrender(session, DOM.div(root, section_wiring(session, list.sections, root);
                                            style=Styles("display" => "contents")))
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
