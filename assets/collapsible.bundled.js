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
        this.onChange = opts.onChange || null;
        this.states = opts.states || [];
        this.lazy = !!this.onExpand;
        this.loaded = !this.lazy;
        this.expanded = this.details ? this.details.open : false;
        if (this.details) {
            this.details.addEventListener('toggle', ()=>this.applyExpanded(this.details.open));
            if (this.states.length > 1) header.addEventListener('click', (e)=>this.cycle(e));
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
    cycle(event) {
        event.preventDefault();
        if (event.target.closest(CONTROL)) return;
        event.stopPropagation();
        const d = this.details;
        const next = d.open ? this.states.indexOf(d.dataset.state) + 1 : 0;
        if (next >= this.states.length) {
            d.open = false;
            return;
        }
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
        this.onChange && this.onChange(expanded);
    }
    showPlaceholder() {
        this.placeholder && this.placeholder(this.body);
    }
    fill(html) {
        if (html != null) this.body.innerHTML = html;
        this.loaded = true;
    }
}
function connect(summary, expanded, states) {
    const c = new Collapsible(summary, null, {
        states,
        onChange: (open)=>{
            if (open !== expanded.value) expanded.notify(open);
        }
    });
    expanded.on((open)=>c.setExpanded(open));
    if (summary.parentElement.open !== expanded.value) expanded.notify(summary.parentElement.open);
}
export { Collapsible as Collapsible };
export { connect as connect };

