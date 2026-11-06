// deno-fmt-ignore-file
// deno-lint-ignore-file
// This code was bundled using `deno bundle` and it's not recommended to edit it manually

class RowBlock {
    constructor(container, opts, hooks){
        this.container = container;
        this.parent = opts.parent || container;
        this.before = opts.before || null;
        this.hooks = hooks;
        this.CHUNK = opts.chunk ?? 40;
        this.MAX_WINDOW = opts.window ?? 160;
        this.start = opts.start || 'bottom';
        this.cache = new Map();
        this.order = [];
        this.count = opts.count ?? Infinity;
        this.seq = null;
        this.plo = 0;
        this.phi = -1;
        this.reqSeq = 0;
        this.pending = {};
        this.epoch = opts.epoch ?? 0;
        this.rowObserver = new ResizeObserver((entries)=>this.onRowsResized(entries));
    }
    hook(name, ...args) {
        const f = this.hooks[name];
        return f ? f(...args) : undefined;
    }
    visible() {
        return this.hooks.visible ? this.hooks.visible() : true;
    }
    frozen() {
        return this.hooks.frozen ? this.hooks.frozen() : false;
    }
    following() {
        return this.hooks.following ? this.hooks.following() : false;
    }
    destroy() {
        this.rowObserver.disconnect();
    }
    seqLength() {
        return this.seq ? this.seq.length : this.count;
    }
    seqIndex(p) {
        return this.seq ? this.seq[p] : p;
    }
    seqPos(idx) {
        if (!this.seq) return idx >= 0 && idx < this.count ? idx : -1;
        let lo = 0, hi = this.seq.length - 1;
        while(lo <= hi){
            const mid = lo + hi >> 1;
            const v = this.seq[mid];
            if (v === idx) return mid;
            if (v < idx) lo = mid + 1;
            else hi = mid - 1;
        }
        return -1;
    }
    blockEmpty() {
        return this.phi < this.plo;
    }
    atTail() {
        return this.phi === this.seqLength() - 1;
    }
    loadStart() {
        const len = this.seqLength();
        if (len === 0) {
            this.clearBlock();
            this.hook('placed', {
                kind: 'empty'
            });
            this.hook('changed');
            return;
        }
        if (this.start === 'bottom') {
            this.requestBlock(Math.max(0, len - this.CHUNK), len - 1, {
                kind: 'tail'
            });
        } else {
            this.requestBlock(0, Math.min(len - 1, this.CHUNK - 1), {
                kind: 'top'
            });
        }
    }
    requestBlock(pa, pb, opts) {
        this.epoch++;
        this.pending = {};
        this.request('block', pa, pb, opts);
    }
    request(slot, pa, pb, opts = {}) {
        if (pa > pb) return;
        const id = ++this.reqSeq;
        this.pending[slot] = {
            ...opts,
            id,
            slot,
            pa,
            pb
        };
        const msg = {
            epoch: this.epoch,
            req: id
        };
        if (this.seq) msg.indices = this.seq.slice(pa, pb + 1);
        else msg.range = [
            pa,
            pb
        ];
        this.hooks.request(msg);
    }
    onRange(msg) {
        if (msg.epoch !== undefined && msg.epoch !== null && msg.epoch !== this.epoch) return;
        const req = Object.values(this.pending).find((r)=>r.id === msg.req);
        if (!req) return;
        delete this.pending[req.slot];
        const data = msg.items ?? [];
        const items = Array.isArray(msg.indices) ? msg.indices.map((idx, i)=>[
                idx,
                data[i]
            ]) : data.map((d, i)=>[
                msg.start + i,
                d
            ]);
        if (!this.seq && this.count === Infinity && !Array.isArray(msg.indices) && req.slot !== 'older' && data.length < req.pb - req.pa + 1) {
            this.count = req.pa + data.length;
        }
        if (req.slot === 'older') this.prependItems(items);
        else if (req.slot === 'newer') this.appendItems(items);
        else this.replaceBlock(items, req);
        this.ensureWindow();
    }
    makeRow(idx, data) {
        const node = this.hooks.makeRow(idx, data);
        node.__blockKey = idx;
        this.cache.set(idx, node);
        return node;
    }
    adoptRows(nodes) {
        this.hook('adopt', nodes);
        for (const node of nodes){
            if (node.offsetParent !== null) node.__btH = node.getBoundingClientRect().height;
            this.rowObserver.observe(node);
        }
    }
    removeRow(idx) {
        const node = this.cache.get(idx);
        if (!node) return;
        this.rowObserver.unobserve(node);
        this.hook('remove', idx, node);
        this.cache.delete(idx);
        node.remove();
    }
    clearBlock() {
        for (const idx of this.order)this.removeRow(idx);
        this.order = [];
        this.plo = 0;
        this.phi = -1;
    }
    insertRows(items, before) {
        const frag = document.createDocumentFragment();
        const nodes = [];
        for (const [idx, data] of items){
            const node = this.makeRow(idx, data);
            frag.appendChild(node);
            nodes.push(node);
        }
        this.parent.insertBefore(frag, before);
        return nodes;
    }
    replaceBlock(items, req) {
        this.clearBlock();
        const rows = items.filter(([, d])=>d != null);
        const nodes = this.insertRows(rows, this.before);
        this.order = rows.map(([idx])=>idx);
        if (this.order.length) {
            this.plo = this.seqPos(this.order[0]);
            this.phi = this.seqPos(this.order[this.order.length - 1]);
        }
        this.adoptRows(nodes);
        this.placeView(req);
    }
    prependItems(items) {
        const rows = items.filter(([idx, d])=>d != null && !this.cache.has(idx));
        if (rows.length === 0) return;
        if (this.seqPos(rows[rows.length - 1][0]) !== this.plo - 1) return;
        const c = this.container;
        const before = c.scrollHeight;
        const top = c.scrollTop;
        const first = this.cache.get(this.order[0]) || this.before;
        const nodes = this.insertRows(rows, first);
        this.order = rows.map(([idx])=>idx).concat(this.order);
        this.plo = this.seqPos(rows[0][0]);
        this.adoptRows(nodes);
        const grown = c.scrollHeight - before;
        if (grown !== 0 && !this.frozen()) {
            c.scrollTop = top + grown;
            this.hook('wrote');
        }
    }
    appendItems(items) {
        const rows = items.filter(([idx, d])=>d != null && !this.cache.has(idx));
        if (rows.length === 0) return;
        if (this.seqPos(rows[0][0]) !== this.phi + 1) return;
        const nodes = this.insertRows(rows, this.before);
        this.order = this.order.concat(rows.map(([idx])=>idx));
        this.phi = this.seqPos(rows[rows.length - 1][0]);
        this.adoptRows(nodes);
        this.hook('appended', nodes);
    }
    pushEnd(idx, data) {
        if (this.cache.has(idx)) return;
        if (this.seq) this.seq.push(idx);
        if (this.seqPos(idx) !== this.phi + 1) return;
        const nodes = this.insertRows([
            [
                idx,
                data
            ]
        ], this.before);
        this.order.push(idx);
        this.phi += 1;
        this.adoptRows(nodes);
    }
    nodeAt(p) {
        if (p < this.plo || p > this.phi) return null;
        return this.cache.get(this.seqIndex(p)) || null;
    }
    placeView(req) {
        const c = this.container;
        const kind = req.kind || 'tail';
        if (kind === 'tail') {
            c.scrollTop = c.scrollHeight;
        } else if (kind === 'top') {
            c.scrollTop = 0;
        } else if (kind === 'restore') {
            this.restoreAnchor({
                idx: req.idx,
                off: req.off
            });
        } else if (kind === 'jump') {
            const node = this.cache.get(this.seqIndex(req.target));
            if (node && node.offsetParent !== null) {
                c.scrollTop = Math.max(0, node.offsetTop - (req.offset ?? 8));
            }
        }
        this.hook('wrote');
        this.hook('placed', req);
    }
    ensureWindow() {
        const c = this.container;
        if (!this.visible() || this.frozen() || c.clientHeight === 0) {
            this.hook('changed');
            return;
        }
        const len = this.seqLength();
        if (this.pending.block || len === 0) {
            this.hook('changed');
            return;
        }
        if (this.blockEmpty()) {
            this.loadStart();
            return;
        }
        const margin = Math.max(800, 2 * c.clientHeight);
        if (this.plo > 0 && !this.pending.older && c.scrollTop < margin) {
            this.request('older', Math.max(0, this.plo - this.CHUNK), this.plo - 1);
        }
        if (this.phi < len - 1 && !this.pending.newer && c.scrollHeight - c.scrollTop - c.clientHeight < margin) {
            this.request('newer', this.phi + 1, Math.min(len - 1, this.phi + this.CHUNK));
        }
        this.trimBlock();
        this.hook('changed');
    }
    visibleSpan() {
        const st = this.container.scrollTop;
        const sb = st + this.container.clientHeight;
        let first = -1, last = -1;
        for(let i = 0; i < this.order.length; i++){
            const node = this.cache.get(this.order[i]);
            if (!node || node.offsetParent === null) continue;
            const top = node.offsetTop;
            if (top + node.offsetHeight <= st + 1) continue;
            if (top >= sb) break;
            if (first < 0) first = i;
            last = i;
        }
        return [
            first,
            last
        ];
    }
    trimBlock() {
        const n = this.order.length;
        if (n <= this.MAX_WINDOW) return;
        const [first, last] = this.visibleSpan();
        if (first < 0) return;
        const c = this.container;
        const excess = n - (this.MAX_WINDOW - this.CHUNK);
        const keepBeyond = Math.floor(this.CHUNK / 2);
        const above = first, below = n - 1 - last;
        const holds = (ids)=>this.hooks.mayDrop ? ids.some((idx)=>!this.hooks.mayDrop(this.cache.get(idx))) : false;
        if (above >= below) {
            const d = Math.min(excess, above - keepBeyond);
            if (d <= 0 || holds(this.order.slice(0, d))) return;
            const before = c.scrollHeight;
            const top = c.scrollTop;
            for (const idx of this.order.splice(0, d))this.removeRow(idx);
            this.plo = this.seqPos(this.order[0]);
            const shrunk = before - c.scrollHeight;
            if (shrunk !== 0) {
                c.scrollTop = top - shrunk;
                this.hook('wrote');
            }
        } else {
            const d = Math.min(excess, below - keepBeyond);
            if (d <= 0 || holds(this.order.slice(n - d))) return;
            for (const idx of this.order.splice(n - d))this.removeRow(idx);
            this.phi = this.seqPos(this.order[this.order.length - 1]);
        }
    }
    onRowsResized(entries) {
        const c = this.container;
        if (!this.visible() || c.clientHeight === 0) return;
        const st = c.scrollTop;
        const sb = st + c.clientHeight;
        const last = this.cache.get(this.order[this.order.length - 1]);
        const rows = entries.map((e)=>[
                e.target,
                e.borderBoxSize && e.borderBoxSize.length ? e.borderBoxSize[0].blockSize : e.target.offsetHeight
            ]).sort(([a], [b])=>a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1);
        let above = 0;
        let shift = 0;
        let grew = false;
        for (const [node, h] of rows){
            const prev = node.__btH;
            node.__btH = h;
            if (prev === undefined || prev === h) continue;
            grew = true;
            this.hook('resized', node);
            const top = node.offsetTop - shift;
            shift += h - prev;
            if (node.offsetParent === null) continue;
            if (top < st - 1 && (top + prev <= st + 1 || top + prev < sb && node !== last)) {
                above += h - prev;
            }
        }
        if (above !== 0 && !this.following() && !this.frozen()) {
            c.scrollTop = st + above;
            this.hook('wrote');
        }
        this.hook('afterResize', grew);
    }
    captureAnchor(skip = null) {
        const st = this.container.scrollTop;
        for (const idx of this.order){
            const n = this.cache.get(idx);
            if (!n || n.offsetParent === null) continue;
            if (skip && skip(n)) continue;
            if (n.offsetTop + n.offsetHeight > st + 4) return {
                idx,
                off: n.offsetTop - st
            };
        }
        return null;
    }
    restoreAnchor(a) {
        if (!a) return;
        const n = this.cache.get(a.idx);
        if (!n || n.offsetParent === null) return;
        const want = Math.max(0, n.offsetTop - a.off);
        if (Math.abs(this.container.scrollTop - want) > 1) {
            this.container.scrollTop = want;
            this.hook('wrote');
        }
    }
    syncRowHeights() {
        for (const idx of this.order){
            const node = this.cache.get(idx);
            if (node) node.__btH = node.getBoundingClientRect().height;
        }
    }
}
class InfiniteList {
    constructor(scroller, rows, toJulia, toJs, opts){
        this.scroller = scroller;
        this.template = document.createElement('template');
        this.block = new RowBlock(scroller, {
            parent: rows,
            chunk: opts.chunk,
            window: opts.window,
            start: 'top',
            epoch: opts.epoch
        }, {
            request: (msg)=>toJulia.notify({
                    type: 'request',
                    epoch: msg.epoch,
                    req: msg.req,
                    start: msg.range[0],
                    stop: msg.range[1]
                }),
            makeRow: (_key, html)=>{
                this.template.innerHTML = html;
                return this.template.content.firstElementChild;
            }
        });
        scroller.addEventListener('scroll', ()=>this.block.ensureWindow(), {
            passive: true
        });
        this.shown = new ResizeObserver(()=>this.block.ensureWindow());
        this.shown.observe(scroller);
        toJs.on((msg)=>{
            if (!scroller.isConnected) {
                this.destroy();
                return false;
            }
            this.dispatch(msg);
        });
        this.block.loadStart();
    }
    destroy() {
        this.block.destroy();
        this.shown.disconnect();
    }
    dispatch(msg) {
        if (msg.type === 'rows') {
            this.block.onRange({
                epoch: msg.epoch,
                req: msg.req,
                start: msg.start,
                items: msg.rows
            });
        } else if (msg.type === 'reset') {
            this.block.clearBlock();
            this.block.count = Infinity;
            this.block.loadStart();
        } else {
            throw new Error(`InfiniteList: unknown message type ${msg.type}`);
        }
    }
}
export { RowBlock as RowBlock };
export { InfiniteList as InfiniteList };

