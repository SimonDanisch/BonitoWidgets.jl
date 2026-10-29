// Endless lists: `RowBlock`, the engine, and `InfiniteList`, the browser side
// of infinite_list.jl. The engine is the one BonitoAgents' chat transcript
// runs on (bonitoagents.js `BonitoChat`), moved here so other apps use the same.
//
// ── The block ────────────────────────────────────────────────────────────────
// The page holds ONE contiguous block of rows: positions [plo, phi] of the
// current sequence, all of them in the DOM in order. A row is identified by
// its KEY (an index into the source); the sequence is every key 0..count-1,
// or a subsequence (`seq`, e.g. a filter's matches). Nothing outside the
// block is in the page, and nothing is estimated: the scroll container is
// exactly as tall as what it shows. Scrolling near an end of the block loads
// the next CHUNK on that side (`ensureWindow`), and a block grown past
// MAX_WINDOW drops rows on the side away from the viewport.
//
// What rows are and how they are fetched belongs to the owner, through hooks:
//
//   request(msg)          REQUIRED. Fetch rows: msg = {epoch, req, range: [pa, pb]}
//                         (positions, inclusive) or {epoch, req, indices: [...]}
//                         (keys) under a subsequence. Answer with `onRange`.
//   makeRow(key, data)    REQUIRED. The node for a row. Not yet in the page.
//   adopt(nodes)          New rows are in the page, before they are measured.
//   remove(key, node)     A row is about to leave the page.
//   mayDrop(node)         false keeps a row in the page when the block trims.
//   placed(req)           A new block is in and the view placed (`placeView`).
//   appended(nodes)       Newer rows went in below the block.
//   wrote()               The block wrote the scroll position.
//   visible()             false: the container is hidden, nothing to measure.
//   frozen()              true: something else owns the scroll position now
//                         (a scrollbar drag): no loading, no correcting.
//   following()           true: the view is pinned to the bottom; growth
//                         chases it instead of being absorbed.
//   resized(node)         A row changed height (once per row and batch).
//   afterResize(grew)     After a batch of row height changes.
//   changed()             The block or the view moved (a position indicator).

export class RowBlock {
    constructor(container, opts, hooks) {
        this.container = container;
        // Rows go into `parent` before `before` (null: at its end).
        this.parent = opts.parent || container;
        this.before = opts.before || null;
        this.hooks = hooks;
        this.CHUNK = opts.chunk ?? 40;          // rows per load at an end of the block
        this.MAX_WINDOW = opts.window ?? 160;   // rows kept before the far side is dropped
        this.start = opts.start || 'bottom';    // where a fresh block opens: 'bottom' | 'top'
        this.cache = new Map();     // key → node, the block's rows only
        this.order = [];            // the block's keys, ascending (= DOM order)
        // Length of the full sequence. Infinity until the source's end is seen
        // (a reply shorter than asked for), for a source that can't count.
        this.count = opts.count ?? Infinity;
        this.seq = null;            // subsequence keys, ascending; null = all
        this.plo = 0;               // block = sequence positions [plo, phi]
        this.phi = -1;
        this.reqSeq = 0;
        this.pending = {};          // kind ('older' | 'newer' | 'block') → in-flight request
        // Bumped whenever the block is replaced or the source SPLICED its rows
        // (every key shifted). Every request carries it and the owner echoes it
        // in the reply, so a reply for a block that is gone is dropped instead
        // of placed among the wrong rows.
        this.epoch = opts.epoch ?? 0;

        // ONE ResizeObserver over the block's rows. A row ABOVE the viewport
        // that changes height (an image or editor reaching its real size, a
        // body mounting) would move everything the reader sees by the
        // difference: the scroll position absorbs it here, before the frame
        // paints. While following the bottom, growth chases it instead.
        // Heights are the fractional BORDER BOX, recorded at adoption.
        this.rowObserver = new ResizeObserver((entries) => this.onRowsResized(entries));
    }

    hook(name, ...args) {
        const f = this.hooks[name];
        return f ? f(...args) : undefined;
    }
    visible() { return this.hooks.visible ? this.hooks.visible() : true; }
    frozen() { return this.hooks.frozen ? this.hooks.frozen() : false; }
    following() { return this.hooks.following ? this.hooks.following() : false; }

    destroy() { this.rowObserver.disconnect(); }

    // ── The sequence ─────────────────────────────────────────────────────────
    seqLength() { return this.seq ? this.seq.length : this.count; }
    seqIndex(p) { return this.seq ? this.seq[p] : p; }
    // Position of key `idx` in the sequence, or -1.
    seqPos(idx) {
        if (!this.seq) return (idx >= 0 && idx < this.count) ? idx : -1;
        let lo = 0, hi = this.seq.length - 1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            const v = this.seq[mid];
            if (v === idx) return mid;
            if (v < idx) lo = mid + 1; else hi = mid - 1;
        }
        return -1;
    }
    blockEmpty() { return this.phi < this.plo; }
    // Does the block end at the last row of the sequence?
    atTail() { return this.phi === this.seqLength() - 1; }

    // ── Loading ──────────────────────────────────────────────────────────────
    // A fresh block where the list opens: the bottom (a conversation) or the top.
    loadStart() {
        const len = this.seqLength();
        if (len === 0) {
            this.clearBlock();
            this.hook('placed', { kind: 'empty' });
            this.hook('changed');
            return;
        }
        if (this.start === 'bottom') {
            this.requestBlock(Math.max(0, len - this.CHUNK), len - 1, { kind: 'tail' });
        } else {
            this.requestBlock(0, Math.min(len - 1, this.CHUNK - 1), { kind: 'top' });
        }
    }

    // Ask for a whole new block, positions [pa, pb]. `opts.kind` says where
    // the view goes when it lands: 'tail' the bottom; 'top' the top; 'jump'
    // position `opts.target` near the top; 'restore' key `opts.idx` back at
    // viewport offset `opts.off`.
    requestBlock(pa, pb, opts) {
        this.epoch++;            // replies for the old block are dead
        this.pending = {};
        this.request('block', pa, pb, opts);
    }

    request(slot, pa, pb, opts = {}) {
        if (pa > pb) return;
        const id = ++this.reqSeq;
        this.pending[slot] = { ...opts, id, slot, pa, pb };
        const msg = { epoch: this.epoch, req: id };
        if (this.seq) msg.indices = this.seq.slice(pa, pb + 1);
        else msg.range = [pa, pb];
        this.hooks.request(msg);
    }

    // The owner's reply: `{epoch, req, start, items}` with `items` the rows'
    // data in order from key `start`, or `{epoch, req, indices, items}` under
    // a subsequence. A null item is a row the source does not have.
    onRange(msg) {
        if (msg.epoch !== undefined && msg.epoch !== null && msg.epoch !== this.epoch) return;
        const req = Object.values(this.pending).find(r => r.id === msg.req);
        if (!req) return;                     // superseded
        delete this.pending[req.slot];
        const data = msg.items ?? [];
        const items = Array.isArray(msg.indices)
            ? msg.indices.map((idx, i) => [idx, data[i]])
            : data.map((d, i) => [msg.start + i, d]);
        // A source that can't count tells its end by a short reply.
        if (!this.seq && this.count === Infinity && !Array.isArray(msg.indices) &&
            req.slot !== 'older' && data.length < req.pb - req.pa + 1) {
            this.count = req.pa + data.length;
        }
        if (req.slot === 'older') this.prependItems(items);
        else if (req.slot === 'newer') this.appendItems(items);
        else this.replaceBlock(items, req);
        this.ensureWindow();
    }

    // ── Rows ─────────────────────────────────────────────────────────────────
    makeRow(idx, data) {
        const node = this.hooks.makeRow(idx, data);
        node.__blockKey = idx;
        this.cache.set(idx, node);
        return node;
    }

    // New rows are in the page: let the owner mount what waited for a
    // document, then record the height each row has now and watch it.
    // Recording here, not on the observer's first report, matters: a body
    // arriving before the next frame would otherwise be that first report,
    // recorded as the start and never compensated. A row without a box
    // (hidden pane, filtered type) records on its first report instead.
    adoptRows(nodes) {
        this.hook('adopt', nodes);
        for (const node of nodes) {
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
        for (const idx of this.order) this.removeRow(idx);
        this.order = [];
        this.plo = 0;
        this.phi = -1;
    }

    // Insert `items` ([[idx, data], ...], ascending) as rows before `before`.
    insertRows(items, before) {
        const frag = document.createDocumentFragment();
        const nodes = [];
        for (const [idx, data] of items) {
            const node = this.makeRow(idx, data);
            frag.appendChild(node);
            nodes.push(node);
        }
        this.parent.insertBefore(frag, before);
        return nodes;
    }

    replaceBlock(items, req) {
        this.clearBlock();
        const rows = items.filter(([, d]) => d != null);
        const nodes = this.insertRows(rows, this.before);
        this.order = rows.map(([idx]) => idx);
        if (this.order.length) {
            this.plo = this.seqPos(this.order[0]);
            this.phi = this.seqPos(this.order[this.order.length - 1]);
        }
        this.adoptRows(nodes);
        this.placeView(req);
    }

    // Older rows, above the block. Everything new is above the reader, so
    // the scroll position grows by exactly what was inserted.
    prependItems(items) {
        const rows = items.filter(([idx, d]) => d != null && !this.cache.has(idx));
        if (rows.length === 0) return;
        if (this.seqPos(rows[rows.length - 1][0]) !== this.plo - 1) return;   // block moved on
        const c = this.container;
        const before = c.scrollHeight;
        const top = c.scrollTop;
        const first = this.cache.get(this.order[0]) || this.before;
        const nodes = this.insertRows(rows, first);
        this.order = rows.map(([idx]) => idx).concat(this.order);
        this.plo = this.seqPos(rows[0][0]);
        // Adopted first: what mounting expands is part of what was inserted.
        this.adoptRows(nodes);
        const grown = c.scrollHeight - before;
        if (grown !== 0 && !this.frozen()) {
            c.scrollTop = top + grown;
            this.hook('wrote');
        }
    }

    // Newer rows, below the block. Rows that arrived meanwhile are already
    // there and skipped.
    appendItems(items) {
        const rows = items.filter(([idx, d]) => d != null && !this.cache.has(idx));
        if (rows.length === 0) return;
        if (this.seqPos(rows[0][0]) !== this.phi + 1) return;   // block moved on
        const nodes = this.insertRows(rows, this.before);
        this.order = this.order.concat(rows.map(([idx]) => idx));
        this.phi = this.seqPos(rows[rows.length - 1][0]);
        this.adoptRows(nodes);
        this.hook('appended', nodes);
    }

    // A new row at the end of the source (a message streamed in). A
    // subsequence's matches are a STATIC set: the row joins it at the end. It
    // goes into the page only when the block reaches the end; otherwise it
    // loads with the rest when the reader gets there.
    pushEnd(idx, data) {
        if (this.cache.has(idx)) return;
        if (this.seq) this.seq.push(idx);
        if (this.seqPos(idx) !== this.phi + 1) return;
        const nodes = this.insertRows([[idx, data]], this.before);
        this.order.push(idx);
        this.phi += 1;
        this.adoptRows(nodes);
    }

    // The node at sequence position `p`, when the block holds it.
    nodeAt(p) {
        if (p < this.plo || p > this.phi) return null;
        return this.cache.get(this.seqIndex(p)) || null;
    }

    // Where the view goes once a new block is in (see `requestBlock`).
    placeView(req) {
        const c = this.container;
        const kind = req.kind || 'tail';
        if (kind === 'tail') {
            c.scrollTop = c.scrollHeight;
        } else if (kind === 'top') {
            c.scrollTop = 0;
        } else if (kind === 'restore') {
            this.restoreAnchor({ idx: req.idx, off: req.off });
        } else if (kind === 'jump') {
            const node = this.cache.get(this.seqIndex(req.target));
            if (node && node.offsetParent !== null) {
                c.scrollTop = Math.max(0, node.offsetTop - (req.offset ?? 8));
            }
        }
        this.hook('wrote');
        this.hook('placed', req);
    }

    // Load more at whichever end of the block the viewport is near, and
    // keep the block bounded. Runs on every scroll and after every insert,
    // so it stops by itself once the viewport is a margin away from both ends.
    ensureWindow() {
        const c = this.container;
        if (!this.visible() || this.frozen() || c.clientHeight === 0) { this.hook('changed'); return; }
        const len = this.seqLength();
        if (this.pending.block || len === 0) { this.hook('changed'); return; }
        if (this.blockEmpty()) { this.loadStart(); return; }
        const margin = Math.max(800, 2 * c.clientHeight);
        if (this.plo > 0 && !this.pending.older && c.scrollTop < margin) {
            this.request('older', Math.max(0, this.plo - this.CHUNK), this.plo - 1);
        }
        if (this.phi < len - 1 && !this.pending.newer &&
            c.scrollHeight - c.scrollTop - c.clientHeight < margin) {
            this.request('newer', this.phi + 1, Math.min(len - 1, this.phi + this.CHUNK));
        }
        this.trimBlock();
        this.hook('changed');
    }

    // Rows of the block whose box meets the viewport, as positions in
    // `order`: [first, last], or [-1, -1]. Hidden rows have no box.
    visibleSpan() {
        const st = this.container.scrollTop;
        const sb = st + this.container.clientHeight;
        let first = -1, last = -1;
        for (let i = 0; i < this.order.length; i++) {
            const node = this.cache.get(this.order[i]);
            if (!node || node.offsetParent === null) continue;
            const top = node.offsetTop;
            if (top + node.offsetHeight <= st + 1) continue;
            if (top >= sb) break;
            if (first < 0) first = i;
            last = i;
        }
        return [first, last];
    }

    // Keep the block at MAX_WINDOW rows: past that, drop rows on the side
    // farther from the viewport, down to MAX_WINDOW - CHUNK, leaving half a
    // chunk beyond the viewport on that side. Rows dropped above the reader
    // take the scroll position down with them. A row the owner holds
    // (`mayDrop`) stays, and so does everything between it and the viewport.
    trimBlock() {
        const n = this.order.length;
        if (n <= this.MAX_WINDOW) return;
        const [first, last] = this.visibleSpan();
        if (first < 0) return;
        const c = this.container;
        const excess = n - (this.MAX_WINDOW - this.CHUNK);
        const keepBeyond = Math.floor(this.CHUNK / 2);
        const above = first, below = n - 1 - last;
        const holds = (ids) => this.hooks.mayDrop
            ? ids.some(idx => !this.hooks.mayDrop(this.cache.get(idx))) : false;
        if (above >= below) {
            const d = Math.min(excess, above - keepBeyond);
            if (d <= 0 || holds(this.order.slice(0, d))) return;
            const before = c.scrollHeight;
            const top = c.scrollTop;
            for (const idx of this.order.splice(0, d)) this.removeRow(idx);
            this.plo = this.seqPos(this.order[0]);
            const shrunk = before - c.scrollHeight;
            if (shrunk !== 0) {
                c.scrollTop = top - shrunk;
                this.hook('wrote');
            }
        } else {
            const d = Math.min(excess, below - keepBeyond);
            if (d <= 0 || holds(this.order.slice(n - d))) return;
            for (const idx of this.order.splice(n - d)) this.removeRow(idx);
            this.phi = this.seqPos(this.order[this.order.length - 1]);
        }
    }

    // ── Holding the reading position ─────────────────────────────────────────
    onRowsResized(entries) {
        // A hidden container (display:none) reports every row at 0. That is
        // no change of the content: skip it, keeping the heights the rows
        // really have, so showing it again reads as no change either.
        const c = this.container;
        if (!this.visible() || c.clientHeight === 0) return;
        const st = c.scrollTop;
        const sb = st + c.clientHeight;
        const last = this.cache.get(this.order[this.order.length - 1]);
        // In page order, so each row's place BEFORE this batch is its place
        // now minus what the changed rows above it grew by (`shift`).
        const rows = entries.map(e => [e.target, (e.borderBoxSize && e.borderBoxSize.length)
                ? e.borderBoxSize[0].blockSize : e.target.offsetHeight])
            .sort(([a], [b]) => (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) ? -1 : 1);
        let above = 0;
        let shift = 0;
        let grew = false;
        for (const [node, h] of rows) {
            const prev = node.__btH;
            node.__btH = h;
            if (prev === undefined || prev === h) continue;
            grew = true;
            this.hook('resized', node);
            const top = node.offsetTop - shift;
            shift += h - prev;
            if (node.offsetParent === null) continue;   // no box, no place
            // The reader keeps the first row that STARTS in the viewport
            // where it is, so every row starting above it absorbs its
            // change: one entirely above, and one reaching in from above.
            // A row covering the whole viewport, or the last one, is what
            // is read, and keeps its own top instead.
            if (top < st - 1 && (top + prev <= st + 1 || (top + prev < sb && node !== last))) {
                above += h - prev;
            }
        }
        if (above !== 0 && !this.following() && !this.frozen()) {
            c.scrollTop = st + above;
            this.hook('wrote');
        }
        this.hook('afterResize', grew);
    }

    // The reading position: the first visible row (not one `skip` names) at
    // or below the viewport top, and its offset from it. A row hanging only
    // a few pixels into the viewport is not what anyone is reading.
    captureAnchor(skip = null) {
        const st = this.container.scrollTop;
        for (const idx of this.order) {
            const n = this.cache.get(idx);
            if (!n || n.offsetParent === null) continue;
            if (skip && skip(n)) continue;
            if (n.offsetTop + n.offsetHeight > st + 4) return { idx, off: n.offsetTop - st };
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

    // Record the heights rows have now, so the row observer sees a
    // deliberate reflow (a filter toggle, already anchored) as no change.
    // The observer's own measure: the fractional border box. `offsetHeight`
    // rounds, and the rounding read as growth, half a pixel per row.
    syncRowHeights() {
        for (const idx of this.order) {
            const node = this.cache.get(idx);
            if (node) node.__btH = node.getBoundingClientRect().height;
        }
    }
}

// ── InfiniteList ─────────────────────────────────────────────────────────────
// A list of static HTML rows over a Julia source (infinite_list.jl), opening
// at the top. Wire, as plain observables: `{type: 'request', epoch, req, start,
// stop}` to Julia (0-based keys, inclusive), `{type: 'rows', epoch, req, start,
// rows}` back (HTML strings, fewer than asked at the source's end; the epoch
// echoed) and `{type: 'reset'}` when the source changed.
export class InfiniteList {
    constructor(scroller, rows, toJulia, toJs, opts) {
        this.scroller = scroller;
        this.template = document.createElement('template');
        this.block = new RowBlock(scroller,
            { parent: rows, chunk: opts.chunk, window: opts.window, start: 'top', epoch: opts.epoch },
            {
                request: (msg) => toJulia.notify({ type: 'request', epoch: msg.epoch, req: msg.req,
                                                   start: msg.range[0], stop: msg.range[1] }),
                makeRow: (_key, html) => {
                    this.template.innerHTML = html;
                    return this.template.content.firstElementChild;
                },
            });
        scroller.addEventListener('scroll', () => this.block.ensureWindow(), { passive: true });
        // A list hidden when it starts (a background tab) loads once it has a size.
        this.shown = new ResizeObserver(() => this.block.ensureWindow());
        this.shown.observe(scroller);
        // A list taken out of the page stops listening (returning false
        // deregisters an observable callback).
        toJs.on(msg => {
            if (!scroller.isConnected) { this.destroy(); return false; }
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
            this.block.onRange({ epoch: msg.epoch, req: msg.req, start: msg.start, items: msg.rows });
        } else if (msg.type === 'reset') {
            // The source changed: its rows are other rows. Start over at the
            // top; the new block's epoch drops replies still on their way.
            this.block.clearBlock();
            this.block.count = Infinity;
            this.block.loadStart();
        } else {
            throw new Error(`InfiniteList: unknown message type ${msg.type}`);
        }
    }
}
