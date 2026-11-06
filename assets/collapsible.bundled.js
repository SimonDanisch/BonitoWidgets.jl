// deno-fmt-ignore-file
// deno-lint-ignore-file
// This code was bundled using `deno bundle` and it's not recommended to edit it manually

const CONTROL = 'a, button, input, select, textarea, [data-bw-control]';
class Collapsible {
    constructor(header, body, opts = {}){
        this.header = header;
        this.body = body;
        this.details = header.tagName === 'SUMMARY' ? header.parentElement : null;
        this.closer = opts.closer || null;
        this.mode = opts.mode || 'once';
        this.onExpand = opts.onExpand || null;
        this.placeholder = opts.placeholder || null;
        this.onToggle = opts.onToggle || null;
        this.lazy = !!this.onExpand;
        this.loaded = !this.lazy;
        this.expanded = this.details ? this.details.open : false;
        if (this.details) {
            this.details.addEventListener('toggle', ()=>this.applyExpanded(this.details.open));
        } else {
            header.style.cursor = 'pointer';
            header.addEventListener('click', (e)=>{
                if (this.expanded && this.closer && !this.closer.contains(e.target)) return;
                this.applyExpanded(!this.expanded);
                this.onToggle && this.onToggle(this.expanded);
            });
        }
    }
    get keepsBody() {
        return this.mode === 'keep' || this.mode === 'compact';
    }
    setExpanded(expanded) {
        if (this.details) {
            this.details.open = expanded;
            return;
        }
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
            const hasBody = this.keepsBody && this.body.childElementCount !== 0;
            if (!hasBody && this.lazy && (!this.loaded || this.mode === 'reload')) {
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
    fill(html) {
        if (html != null) this.body.innerHTML = html;
        this.loaded = true;
    }
}
function cycle(event, d) {
    event.preventDefault();
    if (event.target.closest(CONTROL)) return;
    event.stopPropagation();
    const states = d.dataset.states.split(' ');
    const next = d.open ? states.indexOf(d.dataset.state) + 1 : 0;
    if (next >= states.length) {
        d.open = false;
        return;
    }
    d.dataset.state = states[next];
    d.open = true;
    d.dispatchEvent(new CustomEvent('bw-collapsible-state'));
}
function connect(anchor, fromBrowser, toBrowser, openKeys) {
    const root = anchor.tagName === 'SUMMARY' ? anchor.parentElement : anchor;
    const ours = (d)=>d.tagName === 'DETAILS' && d.dataset.bwKey !== undefined && d.closest('[data-bw-sections]') === root;
    const section = (key)=>root.dataset.bwKey === String(key) ? root : root.querySelector(`:scope > [data-bw-key="${key}"]`);
    root.addEventListener('toggle', (e)=>{
        if (ours(e.target)) fromBrowser.notify([
            Number(e.target.dataset.bwKey),
            e.target.open
        ]);
    }, true);
    root.addEventListener('click', (e)=>{
        const summary = e.target.closest('summary');
        const d = summary && summary.parentElement;
        if (d && d.dataset.states && ours(d)) cycle(e, d);
    });
    toBrowser.on(([key, open])=>{
        const d = section(key);
        if (d) d.open = open;
    });
    const wasOpen = new Set(openKeys);
    const all = root.dataset.bwKey !== undefined ? [
        root
    ] : root.querySelectorAll(':scope > [data-bw-key]');
    for (const d of all){
        const key = Number(d.dataset.bwKey);
        if (d.open !== wasOpen.has(key)) fromBrowser.notify([
            key,
            d.open
        ]);
    }
}
export { Collapsible as Collapsible };
export { connect as connect };

