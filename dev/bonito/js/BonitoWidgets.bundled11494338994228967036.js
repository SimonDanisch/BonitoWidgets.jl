// deno-fmt-ignore-file
// deno-lint-ignore-file
// This code was bundled using `deno bundle` and it's not recommended to edit it manually

const ICON_CLOSE = '<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"></path></svg>';
const ICON_DOCK = '<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="1.5"></rect><path d="M8 4.5v5M5.5 7L8 9.5 10.5 7"></path></svg>';
function mountWorkspace(opts) {
    const chrome = opts.chrome;
    const wsRoot = chrome.closest('.bw-ws');
    const parking = opts.parking;
    const floatlayer = opts.floatlayer;
    const layoutObs = opts.layout;
    const metaObs = opts.meta;
    const closedObs = opts.closed;
    const minFrac = opts.minFraction;
    const hideSingleTab = opts.hideSingleTab;
    const clone = (x)=>JSON.parse(JSON.stringify(x));
    let layout = clone(layoutObs.value);
    let meta = metaObs.value || {};
    const narrow = window.matchMedia('(max-width: 700px)');
    const labelOf = (id)=>meta[id] && meta[id].label != null ? meta[id].label : id;
    const closableOf = (id)=>!!(meta[id] && meta[id].closable);
    const panelNode = (id)=>wsRoot.querySelector('.bw-ws-panel[data-panel-id="' + (window.CSS ? CSS.escape(id) : id) + '"]');
    const isLeaf = (node)=>node.type === 'tabs';
    function leafOf(node, id) {
        if (isLeaf(node)) return node.panels.includes(id) ? node : null;
        for (const c of node.children){
            const f = leafOf(c, id);
            if (f) return f;
        }
        return null;
    }
    function normalize(node) {
        if (isLeaf(node)) return node.panels.length ? node : null;
        const kids = [], fracs = [];
        node.children.forEach((c, i)=>{
            const k = normalize(c);
            if (k) {
                kids.push(k);
                fracs.push(node.fractions[i] || 1);
            }
        });
        if (kids.length === 0) return null;
        if (kids.length === 1) return kids[0];
        const s = fracs.reduce((a, b)=>a + b, 0);
        node.children = kids;
        node.fractions = fracs.map((f)=>f / s);
        return node;
    }
    function replaceNode(node, target, repl) {
        if (node === target) return repl;
        if (!isLeaf(node)) node.children = node.children.map((c)=>replaceNode(c, target, repl));
        return node;
    }
    function allPanels(node, out = []) {
        if (isLeaf(node)) out.push(...node.panels);
        else node.children.forEach((c)=>allPanels(c, out));
        return out;
    }
    function firstActive() {
        let node = layout.root;
        while(!isLeaf(node))node = node.children[0];
        return node.active;
    }
    let suppressClick = false;
    let suppressRender = false;
    function setActiveLocal(leaf, id) {
        leaf.active = id;
        for (const g of chrome.querySelectorAll('.bw-ws-group')){
            if (g._node !== leaf) continue;
            for (const b of g._strip.children)b.classList.toggle('bw-active', b._panelId === id);
            leaf.panels.forEach((pid)=>{
                const node = panelNode(pid);
                if (node && g._body.contains(node)) {
                    const on = pid === id;
                    node.style.visibility = on ? 'visible' : 'hidden';
                    node.style.pointerEvents = on ? 'auto' : 'none';
                }
            });
            return;
        }
    }
    function parkAll() {
        wsRoot.querySelectorAll('.bw-ws-panel').forEach((p)=>{
            if (p.parentNode !== parking) parking.appendChild(p);
        });
    }
    function snapshotScroll() {
        const snap = [];
        wsRoot.querySelectorAll('.bw-ws-panel *').forEach((el)=>{
            if (el.scrollTop || el.scrollLeft) {
                const atBottom = el.scrollHeight - el.clientHeight - el.scrollTop <= 2;
                snap.push([
                    el,
                    el.scrollTop,
                    el.scrollLeft,
                    atBottom
                ]);
            }
        });
        return snap;
    }
    function restoreScroll(snap, frames) {
        for (const [el, t, l, atBottom] of snap){
            if (!el.isConnected) continue;
            const want = atBottom ? el.scrollHeight - el.clientHeight : t;
            if (Math.abs(el.scrollTop - want) > 1) el.scrollTop = want;
            if (Math.abs(el.scrollLeft - l) > 1) el.scrollLeft = l;
        }
        if (frames > 0) requestAnimationFrame(()=>restoreScroll(snap, frames - 1));
    }
    function placePanel(body, id, activeId) {
        const p = panelNode(id);
        if (!p) return;
        body.appendChild(p);
        const on = id === activeId;
        p.style.visibility = on ? 'visible' : 'hidden';
        p.style.pointerEvents = on ? 'auto' : 'none';
    }
    function buildLeaf(leaf, bare) {
        const group = document.createElement('div');
        group.className = 'bw-ws-group';
        const bar = document.createElement('div');
        bar.className = 'bw-group-bar';
        const strip = document.createElement('div');
        strip.className = 'bw-group-tabs';
        bar.appendChild(strip);
        const body = document.createElement('div');
        body.className = 'bw-ws-body';
        if (!bare) group.appendChild(bar);
        group.appendChild(body);
        group._node = leaf;
        group._strip = strip;
        group._body = body;
        leaf.panels.forEach((id)=>{
            const btn = document.createElement('button');
            btn.className = id === leaf.active ? 'bw-tab bw-active' : 'bw-tab';
            btn._panelId = id;
            const text = document.createElement('span');
            text.className = 'bw-tab-label';
            text.textContent = labelOf(id);
            btn.appendChild(text);
            if (closableOf(id)) {
                const close = document.createElement('button');
                close.className = 'bw-tab-close';
                close.innerHTML = ICON_CLOSE;
                close.title = 'Close';
                close.addEventListener('pointerdown', (e)=>e.stopPropagation());
                close.addEventListener('click', (e)=>{
                    e.stopPropagation();
                    closedObs.notify(id);
                });
                btn.appendChild(close);
            }
            btn.addEventListener('click', ()=>{
                if (suppressClick) {
                    suppressClick = false;
                    return;
                }
                if (leaf.active === id) return;
                setActiveLocal(leaf, id);
                notifyLayout(true);
            });
            if (!narrow.matches) btn.addEventListener('pointerdown', (e)=>startTabDrag(e, id, btn));
            strip.appendChild(btn);
            placePanel(body, id, leaf.active);
        });
        return group;
    }
    function buildSplit(node) {
        const el = document.createElement('div');
        el.className = 'bw-ws-split';
        el.style.display = 'flex';
        el.style.flexDirection = node.type === 'row' ? 'row' : 'column';
        el.style.minWidth = '0';
        el.style.minHeight = '0';
        node.children.forEach((child, i)=>{
            const cel = buildNode(child);
            cel.style.flex = node.fractions[i] + ' 1 0%';
            el.appendChild(cel);
            if (i < node.children.length - 1) el.appendChild(buildGutter(node, i, el));
        });
        return el;
    }
    function buildGutter(node, i, splitEl) {
        const gutter = document.createElement('div');
        gutter.className = 'bw-group-gutter bw-split-gutter';
        gutter.style.flex = '0 0 var(--bw-gutter-size)';
        gutter.style.display = 'flex';
        const grip = document.createElement('div');
        grip.className = 'bw-split-grip';
        gutter.appendChild(grip);
        gutter.style.cursor = node.type === 'row' ? 'col-resize' : 'row-resize';
        let dragging = false, combinedStart = 0, combinedSize = 0, total = 0, elA = null, elB = null;
        gutter.addEventListener('pointerdown', (e)=>{
            elA = splitEl.children[2 * i];
            elB = splitEl.children[2 * i + 2];
            const ra = elA.getBoundingClientRect();
            const rb = elB.getBoundingClientRect();
            if (node.type === 'row') {
                combinedStart = ra.left;
                combinedSize = rb.right - ra.left;
            } else {
                combinedStart = ra.top;
                combinedSize = rb.bottom - ra.top;
            }
            total = node.fractions[i] + node.fractions[i + 1];
            dragging = true;
            chrome.classList.add('bw-dragging');
            gutter.setPointerCapture(e.pointerId);
            e.preventDefault();
        });
        gutter.addEventListener('pointermove', (e)=>{
            if (!dragging) return;
            const pos = node.type === 'row' ? e.clientX : e.clientY;
            let fa = (pos - combinedStart) / combinedSize * total;
            fa = Math.min(Math.max(fa, minFrac), total - minFrac);
            node.fractions[i] = fa;
            node.fractions[i + 1] = total - fa;
            elA.style.flex = fa + ' 1 0%';
            elB.style.flex = total - fa + ' 1 0%';
        });
        const endDrag = (e)=>{
            if (!dragging) return;
            dragging = false;
            chrome.classList.remove('bw-dragging');
            try {
                gutter.releasePointerCapture(e.pointerId);
            } catch (_) {}
            notifyLayout();
        };
        gutter.addEventListener('pointerup', endDrag);
        gutter.addEventListener('pointercancel', endDrag);
        return gutter;
    }
    const buildNode = (node)=>isLeaf(node) ? buildLeaf(node) : buildSplit(node);
    function buildFloat(f) {
        const win = document.createElement('div');
        win.className = 'bw-float bw-ws-float';
        win._float = f;
        const titleBar = document.createElement('div');
        titleBar.className = 'bw-float-title';
        const titleText = document.createElement('span');
        titleText.className = 'bw-float-title-text';
        titleText.textContent = labelOf(f.panel);
        const dockBtn = document.createElement('button');
        dockBtn.className = 'bw-icon-btn bw-float-dock';
        dockBtn.innerHTML = ICON_DOCK;
        dockBtn.title = 'Dock';
        const closeBtn = document.createElement('button');
        closeBtn.className = 'bw-icon-btn bw-float-close';
        closeBtn.innerHTML = ICON_CLOSE;
        closeBtn.title = closableOf(f.panel) ? 'Close' : 'Dock';
        titleBar.appendChild(titleText);
        titleBar.appendChild(dockBtn);
        titleBar.appendChild(closeBtn);
        const body = document.createElement('div');
        body.className = 'bw-float-body';
        const resize = document.createElement('div');
        resize.className = 'bw-float-resize';
        resize.title = 'Drag to resize';
        win.appendChild(titleBar);
        win.appendChild(body);
        win.appendChild(resize);
        win.style.left = f.x + 'px';
        win.style.top = f.y + 'px';
        win.style.width = f.width + 'px';
        win.style.height = f.height + 'px';
        const p = panelNode(f.panel);
        if (p) {
            body.appendChild(p);
            p.style.visibility = 'visible';
            p.style.pointerEvents = 'auto';
        }
        dockBtn.addEventListener('click', (e)=>{
            e.stopPropagation();
            dockFloat(f.panel);
        });
        closeBtn.addEventListener('click', (e)=>{
            e.stopPropagation();
            if (closableOf(f.panel)) closedObs.notify(f.panel);
            else dockFloat(f.panel);
        });
        wireFloatDrag(win, titleBar, f);
        wireFloatResize(win, resize, f);
        return win;
    }
    let placedIds = new Set();
    function render() {
        const scrollSnap = snapshotScroll();
        parkAll();
        const layoutIds = new Set(allPanels(layout.root).concat(layout.floating.map((f)=>f.panel)));
        wsRoot.querySelectorAll('.bw-ws-panel').forEach((p)=>{
            const id = p.dataset.panelId;
            if (!layoutIds.has(id) && placedIds.has(id)) p.remove();
        });
        if (narrow.matches) {
            const ids = allPanels(layout.root).concat(layout.floating.map((f)=>f.panel));
            const active = ids.length ? ids.includes(firstActive()) ? firstActive() : ids[0] : '';
            chrome.replaceChildren(buildLeaf({
                type: 'tabs',
                panels: ids,
                active
            }, hideSingleTab && ids.length === 1));
            floatlayer.replaceChildren();
        } else {
            const bareRoot = hideSingleTab && isLeaf(layout.root) && layout.root.panels.length === 1 && layout.floating.length === 0;
            chrome.replaceChildren(bareRoot ? buildLeaf(layout.root, true) : buildNode(layout.root));
            floatlayer.replaceChildren(...layout.floating.map(buildFloat));
        }
        placedIds = layoutIds;
        const rootEl = chrome.firstElementChild;
        if (rootEl) rootEl.style.flex = '1 1 0';
        chrome.style.display = 'flex';
        parking.style.display = 'none';
        restoreScroll(scrollSnap, 20);
    }
    function notifyLayout(local) {
        if (local) suppressRender = true;
        layoutObs.notify(clone(layout));
        suppressRender = false;
    }
    let renderQueued = false;
    const scheduleRender = ()=>{
        if (renderQueued) return;
        renderQueued = true;
        requestAnimationFrame(()=>{
            renderQueued = false;
            render();
        });
    };
    wsRoot.__bwScheduleRender = scheduleRender;
    layoutObs.on((v)=>{
        if (suppressRender) return;
        layout = clone(v);
        render();
    });
    metaObs.on((m)=>{
        meta = m || {};
        render();
    });
    const onNarrow = ()=>render();
    if (narrow.addEventListener) narrow.addEventListener('change', onNarrow);
    else narrow.addListener(onNarrow);
    const overlay = document.createElement('div');
    overlay.className = 'bw-drop-overlay';
    overlay.style.position = 'fixed';
    overlay.style.display = 'none';
    overlay.style.pointerEvents = 'none';
    overlay.style.zIndex = 'calc(var(--bw-z-float) + 1)';
    document.body.appendChild(overlay);
    let markedBtn = null;
    const clearMark = ()=>{
        if (markedBtn) markedBtn.classList.remove('bw-drop-before', 'bw-drop-after');
        markedBtn = null;
    };
    function dropActionAt(e, allowFloat) {
        for (const group of chrome.querySelectorAll('.bw-ws-group')){
            const barR = group.firstElementChild.getBoundingClientRect();
            if (e.clientY >= barR.top && e.clientY <= barR.bottom && e.clientX >= barR.left && e.clientX <= barR.right) {
                for (const btn of group._strip.children){
                    const tr = btn.getBoundingClientRect();
                    if (e.clientX >= tr.left && e.clientX <= tr.right) {
                        const before = e.clientX < (tr.left + tr.right) / 2;
                        return {
                            leaf: group._node,
                            kind: 'strip',
                            btn,
                            before
                        };
                    }
                }
                return {
                    leaf: group._node,
                    kind: 'strip',
                    btn: null,
                    before: false
                };
            }
            const r = group._body.getBoundingClientRect();
            if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) continue;
            const fx = (e.clientX - r.left) / r.width;
            const fy = (e.clientY - r.top) / r.height;
            let kind = 'center';
            if (fx < 0.2) kind = 'left';
            else if (fx > 0.8) kind = 'right';
            else if (fy < 0.25) kind = 'top';
            else if (fy > 0.75) kind = 'bottom';
            return {
                leaf: group._node,
                kind,
                rect: r
            };
        }
        if (allowFloat) {
            const cr = chrome.getBoundingClientRect();
            if (e.clientX < cr.left || e.clientX > cr.right || e.clientY < cr.top || e.clientY > cr.bottom) {
                return {
                    kind: 'float'
                };
            }
        }
        return null;
    }
    function showAction(action) {
        clearMark();
        if (!action || action.kind === 'strip') {
            overlay.style.display = 'none';
            if (action && action.btn) {
                markedBtn = action.btn;
                markedBtn.classList.add(action.before ? 'bw-drop-before' : 'bw-drop-after');
            }
            return;
        }
        if (action.kind === 'float') {
            overlay.style.display = 'none';
            return;
        }
        const r = action.rect;
        let { left , top , width , height  } = r;
        if (action.kind === 'left') width /= 2;
        if (action.kind === 'right') {
            width /= 2;
            left += width;
        }
        if (action.kind === 'top') height /= 2;
        if (action.kind === 'bottom') {
            height /= 2;
            top += height;
        }
        overlay.style.display = 'block';
        overlay.style.left = left + 'px';
        overlay.style.top = top + 'px';
        overlay.style.width = width + 'px';
        overlay.style.height = height + 'px';
    }
    function dockInto(id, action) {
        if (action.kind === 'center') {
            action.leaf.panels.push(id);
            action.leaf.active = id;
        } else if (action.kind === 'strip') {
            let pos = action.leaf.panels.length;
            if (action.btn) {
                pos = action.leaf.panels.indexOf(action.btn._panelId);
                if (pos < 0) pos = action.leaf.panels.length;
                else if (!action.before) pos += 1;
            }
            action.leaf.panels.splice(pos, 0, id);
            action.leaf.active = id;
        } else {
            const newLeaf = {
                type: 'tabs',
                panels: [
                    id
                ],
                active: id
            };
            const dir = action.kind === 'left' || action.kind === 'right' ? 'row' : 'column';
            const before = action.kind === 'left' || action.kind === 'top';
            const split = {
                type: dir,
                children: before ? [
                    newLeaf,
                    action.leaf
                ] : [
                    action.leaf,
                    newLeaf
                ],
                fractions: [
                    0.5,
                    0.5
                ]
            };
            layout.root = replaceNode(layout.root, action.leaf, split);
        }
    }
    function applyTabDrop(id, action) {
        const src = leafOf(layout.root, id);
        if (action.kind !== 'float' && action.leaf === src && src.panels.length === 1 && (action.kind === 'center' || action.kind === 'strip')) return;
        src.panels = src.panels.filter((p)=>p !== id);
        if (src.active === id) src.active = src.panels[0] || '';
        if (action.kind === 'float') {
            const wr = wsRoot.getBoundingClientRect();
            const x = Math.max(0, Math.round(action.clientX - wr.left - 40));
            const y = Math.max(0, Math.round(action.clientY - wr.top - 16));
            layout.floating.push({
                panel: id,
                x,
                y,
                width: 480,
                height: 320
            });
        } else {
            dockInto(id, action);
        }
        layout.root = normalize(layout.root) || {
            type: 'tabs',
            panels: [],
            active: ''
        };
        notifyLayout();
    }
    function startTabDrag(e, id, btn) {
        if (e.button !== undefined && e.button !== 0) return;
        const startX = e.clientX, startY = e.clientY;
        let engaged = false, ghost = null, action = null;
        const onMove = (e2)=>{
            if (!engaged) {
                if (Math.hypot(e2.clientX - startX, e2.clientY - startY) < 6) return;
                engaged = true;
                btn.classList.add('bw-drag-src');
                ghost = document.createElement('div');
                ghost.className = 'bw-drag-ghost';
                ghost.textContent = labelOf(id);
                document.body.appendChild(ghost);
            }
            ghost.style.left = e2.clientX + 10 + 'px';
            ghost.style.top = e2.clientY + 14 + 'px';
            action = dropActionAt(e2, true);
            if (action && action.kind === 'float') {
                action.clientX = e2.clientX;
                action.clientY = e2.clientY;
            }
            showAction(action);
        };
        const finish = (apply)=>{
            window.removeEventListener('pointermove', onMove);
            window.removeEventListener('pointerup', onUp);
            window.removeEventListener('pointercancel', onCancel);
            if (!engaged) return;
            suppressClick = true;
            btn.classList.remove('bw-drag-src');
            if (ghost) ghost.remove();
            overlay.style.display = 'none';
            clearMark();
            if (apply && action) applyTabDrop(id, action);
        };
        const onUp = ()=>finish(true);
        const onCancel = ()=>finish(false);
        window.addEventListener('pointermove', onMove);
        window.addEventListener('pointerup', onUp);
        window.addEventListener('pointercancel', onCancel);
    }
    const wsRect = ()=>wsRoot.getBoundingClientRect();
    const clampFloatX = (x)=>Math.max(0, Math.min(wsRoot.clientWidth - 48, x));
    const clampFloatY = (y)=>Math.max(0, Math.min(wsRoot.clientHeight - 32, y));
    function dockFloat(id, action) {
        layout.floating = layout.floating.filter((f)=>f.panel !== id);
        if (action) dockInto(id, action);
        else {
            const leaf = firstLeafNode();
            leaf.panels.push(id);
            leaf.active = id;
        }
        layout.root = normalize(layout.root) || {
            type: 'tabs',
            panels: [
                id
            ],
            active: id
        };
        notifyLayout();
    }
    function firstLeafNode() {
        let node = layout.root;
        while(!isLeaf(node))node = node.children[0];
        return node;
    }
    function wireFloatDrag(win, titleBar, f) {
        titleBar.addEventListener('pointerdown', (ev)=>{
            if (ev.target.closest('.bw-float-close, .bw-float-dock')) return;
            if (ev.button !== undefined && ev.button !== 0) return;
            win.classList.add('bw-float-active');
            const rect = wsRect();
            const offX = ev.clientX - (f.x + rect.left);
            const offY = ev.clientY - (f.y + rect.top);
            let lastX = f.x, lastY = f.y, action = null;
            const onMove = (e2)=>{
                const r = wsRect();
                lastX = clampFloatX(e2.clientX - r.left - offX);
                lastY = clampFloatY(e2.clientY - r.top - offY);
                win.style.left = lastX + 'px';
                win.style.top = lastY + 'px';
                const a = dropActionAt(e2, false);
                action = a && a.kind !== 'center' ? a : null;
                showAction(action);
            };
            const onUp = ()=>{
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
                overlay.style.display = 'none';
                clearMark();
                win.classList.remove('bw-float-active');
                if (action) {
                    dockFloat(f.panel, action);
                    return;
                }
                f.x = Math.round(lastX);
                f.y = Math.round(lastY);
                notifyLayout();
            };
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
            ev.preventDefault();
        });
    }
    function wireFloatResize(win, handle, f) {
        handle.addEventListener('pointerdown', (ev)=>{
            const startW = win.offsetWidth, startH = win.offsetHeight;
            const startX = ev.clientX, startY = ev.clientY;
            let lastW = startW, lastH = startH;
            const onMove = (e2)=>{
                lastW = Math.max(200, Math.min(wsRoot.clientWidth, startW + (e2.clientX - startX)));
                lastH = Math.max(120, Math.min(wsRoot.clientHeight, startH + (e2.clientY - startY)));
                win.style.width = lastW + 'px';
                win.style.height = lastH + 'px';
            };
            const onUp = ()=>{
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
                f.width = Math.round(lastW);
                f.height = Math.round(lastH);
                notifyLayout();
            };
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
            ev.preventDefault();
            ev.stopPropagation();
        });
    }
    render();
}
export { mountWorkspace as mountWorkspace };

