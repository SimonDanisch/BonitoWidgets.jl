// The browser side of `Collapsible`. A section rendered in Julia is a <details>, and
// the browser handles its click, so it has no script of its own: `connect` is one
// listener for a whole list of them. `Collapsible` the class is for rows built in the
// browser, which have their own script anyway and may not be able to be a <details>,
// such as a body that stays visible while collapsed.

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
        this.lazy = !!this.onExpand;
        this.loaded = !this.lazy;
        this.expanded = this.details ? this.details.open : false;

        if (this.details) {
            this.details.addEventListener('toggle', () => this.applyExpanded(this.details.open));
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

// Closed -> first state -> ... -> last state -> closed.
function cycle(event, d) {
    event.preventDefault();
    if (event.target.closest(CONTROL)) return;
    event.stopPropagation();
    const states = d.dataset.states.split(' ');
    const next = d.open ? states.indexOf(d.dataset.state) + 1 : 0;
    if (next >= states.length) { d.open = false; return; }
    d.dataset.state = states[next];
    d.open = true;
    d.dispatchEvent(new CustomEvent('bw-collapsible-state'));
}

// One listener for the sections of a `CollapsibleList`, or for a single `Collapsible`,
// whose <summary> `anchor` is then. `fromBrowser` and `toBrowser` carry [key, open].
export function connect(anchor, fromBrowser, toBrowser, openKeys) {
    const root = anchor.tagName === 'SUMMARY' ? anchor.parentElement : anchor;
    // A section's own <summary> can hold or sit in another list's sections.
    const ours = (d) => d.tagName === 'DETAILS' && d.dataset.bwKey !== undefined &&
        d.closest('[data-bw-sections]') === root;
    const section = (key) => root.dataset.bwKey === String(key) ? root :
        root.querySelector(`:scope > [data-bw-key="${key}"]`);
    // `toggle` doesn't bubble, so catch it on the way down.
    root.addEventListener('toggle', (e) => {
        if (ours(e.target)) fromBrowser.notify([Number(e.target.dataset.bwKey), e.target.open]);
    }, true);
    root.addEventListener('click', (e) => {
        const summary = e.target.closest('summary');
        const d = summary && summary.parentElement;
        if (d && d.dataset.states && ours(d)) cycle(e, d);
    });
    toBrowser.on(([key, open]) => {
        const d = section(key);
        if (d) d.open = open;
    });
    // Clicked before this module arrived.
    const wasOpen = new Set(openKeys);
    const all = root.dataset.bwKey !== undefined ? [root] : root.querySelectorAll(':scope > [data-bw-key]');
    for (const d of all) {
        const key = Number(d.dataset.bwKey);
        if (d.open !== wasOpen.has(key)) fromBrowser.notify([key, d.open]);
    }
}
