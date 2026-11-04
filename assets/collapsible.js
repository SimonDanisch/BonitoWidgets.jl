// The browser side of `Collapsible`: what a click does, when the body loads and
// what a collapsed body does. A <summary> header keeps its state in the <details>'
// `open`, and the browser handles the click. Any other header and body are for
// rows built in the browser that can't be a <details>, such as a body that stays
// visible while collapsed.

const CONTROL = 'a, button, input, select, textarea, [data-bw-control]';

// What the body does across a collapse, and when it loads:
//   once     hidden, loaded on the first open
//   reload   emptied, loaded on every open
//   keep     hidden and stays mounted, loaded when it's empty
//   compact  stays visible and mounted, loaded when it's empty. CSS sizes it from
//            the header's `data-expanded`.
export class Collapsible {
    constructor(header, body, opts = {}) {
        this.header = header;
        this.body = body;
        this.details = header.tagName === 'SUMMARY' ? header.parentElement : null;
        // Open, only this element closes: a header dense with small buttons is
        // easy to miss, and a near miss shouldn't close the body.
        this.closer = opts.closer || null;
        this.mode = opts.mode || 'once';
        this.onExpand = opts.onExpand || null;      // load the body
        this.placeholder = opts.placeholder || null;
        this.onToggle = opts.onToggle || null;      // the reader's own clicks
        this.onChange = opts.onChange || null;      // any change
        // The open states a click cycles through, before closing (`data-state`).
        this.states = opts.states || [];
        this.lazy = !!this.onExpand;
        this.loaded = !this.lazy;
        this.expanded = this.details ? this.details.open : false;

        if (this.details) {
            this.details.addEventListener('toggle', () => this.applyExpanded(this.details.open));
            if (this.states.length > 1) header.addEventListener('click', (e) => this.cycle(e));
        } else {
            header.style.cursor = 'pointer';
            header.addEventListener('click', (e) => {
                if (this.expanded && this.closer && !this.closer.contains(e.target)) return;
                this.applyExpanded(!this.expanded);
                this.onToggle && this.onToggle(this.expanded);
            });
        }
    }

    get keepsBody() { return this.mode === 'keep' || this.mode === 'compact'; }

    setExpanded(expanded) {
        if (this.details) { this.details.open = expanded; return; }
        this.applyExpanded(expanded);
    }

    // Closed -> first state -> ... -> last state -> closed.
    cycle(event) {
        event.preventDefault();
        if (event.target.closest(CONTROL)) return;
        event.stopPropagation();
        const d = this.details;
        const next = d.open ? this.states.indexOf(d.dataset.state) + 1 : 0;
        if (next >= this.states.length) { d.open = false; return; }
        d.dataset.state = this.states[next];
        d.open = true;
        d.dispatchEvent(new CustomEvent('bw-collapsible-state'));
    }

    applyExpanded(expanded) {
        if (expanded === this.expanded) return;
        this.expanded = expanded;
        if (!this.details) {
            this.header.dataset.expanded = expanded ? 'true' : 'false';
            if (this.closer) this.closer.textContent = expanded ? '▼' : '▶';
            this.body.style.display = expanded || this.mode === 'compact' ? '' : 'none';
        }
        if (expanded) {
            // A replayed row can start with an empty body even in a mode that
            // keeps it, so those load whenever there's nothing to show.
            const hasBody = this.keepsBody && this.body.childElementCount !== 0;
            if (!hasBody && this.lazy && (!this.loaded || this.mode === 'reload')) {
                // Marked before notifying: an update arriving before the body
                // must not render it a second time over an initializing editor.
                this.loaded = true;
                this.showPlaceholder();
                this.onExpand();
            }
        } else if (this.mode === 'reload') {
            this.body.innerHTML = '';
            this.loaded = false;
        }
        this.onChange && this.onChange(expanded);
    }

    showPlaceholder() {
        this.placeholder && this.placeholder(this.body);
    }

    // The body arrived. Its next open shows it without loading again.
    fill(html) {
        if (html != null) this.body.innerHTML = html;
        this.loaded = true;
    }
}

// A section rendered in Julia: `expanded` and the element's `open` follow each other.
export function connect(summary, expanded, states) {
    const c = new Collapsible(summary, null, {
        states,
        onChange: (open) => { if (open !== expanded.value) expanded.notify(open); },
    });
    expanded.on((open) => c.setExpanded(open));
    // Clicked before this module arrived.
    if (summary.parentElement.open !== expanded.value) expanded.notify(summary.parentElement.open);
}
