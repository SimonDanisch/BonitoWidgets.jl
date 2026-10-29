// deno-fmt-ignore-file
// deno-lint-ignore-file
// This code was bundled using `deno bundle` and it's not recommended to edit it manually

class Overlay {
    constructor(root, open, openClass){
        this.root = root;
        this.open = open;
        this.openClass = openClass;
        this.dismiss = null;
        open.on((value)=>{
            this.show(value);
        });
        this.show(open.value);
    }
    listen(signal) {}
    show(value) {
        this.root.classList.toggle(this.openClass, value);
        if (value === (this.dismiss !== null)) return;
        if (value) {
            this.dismiss = new AbortController();
            this.listen(this.dismiss.signal);
        } else {
            this.dismiss.abort();
            this.dismiss = null;
        }
    }
    alive() {
        if (this.root.isConnected) return true;
        if (this.dismiss) {
            this.dismiss.abort();
            this.dismiss = null;
        }
        return false;
    }
    close() {
        if (this.alive()) this.open.notify(false);
    }
}
class Menu extends Overlay {
    constructor(root, trigger, list, open, closeOnPick){
        super(root, open, 'bw-menu-open');
        trigger.addEventListener('click', (event)=>{
            event.stopPropagation();
            open.notify(!open.value);
        });
        if (closeOnPick) list.addEventListener('click', (event)=>{
            if (event.target.closest('.bw-menu-item')) open.notify(false);
        });
    }
    listen(signal) {
        document.addEventListener('click', (event)=>{
            if (!this.root.contains(event.target)) this.close();
        }, {
            capture: true,
            signal
        });
        document.addEventListener('keydown', (event)=>{
            if (event.key === 'Escape') this.close();
        }, {
            capture: true,
            signal
        });
    }
}
class Modal extends Overlay {
    constructor(overlay, closeButton, open){
        super(overlay, open, 'bw-modal-open');
        closeButton.addEventListener('click', ()=>open.notify(false));
        let downOnBackdrop = false;
        overlay.addEventListener('pointerdown', (event)=>{
            downOnBackdrop = event.target === overlay;
        });
        overlay.addEventListener('click', (event)=>{
            if (downOnBackdrop && event.target === overlay) open.notify(false);
            downOnBackdrop = false;
        });
    }
    listen(signal) {
        document.addEventListener('keydown', (event)=>{
            if (event.key !== 'Escape') return;
            event.stopPropagation();
            this.close();
        }, {
            capture: true,
            signal
        });
    }
}
export { Menu as Menu };
export { Modal as Modal };
