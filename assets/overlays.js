// Popover menus and modal dialogs (overlays.jl).
//
// Each widget's `jsrender` creates one instance with its DOM nodes and its
// `open` observable. The instance follows `open`, whether the browser or Julia
// changed it, and listens on the document only while open: every document
// listener is registered with the AbortController of the current open, so
// closing removes all of them at once.
//
// An overlay can leave the page while open (a re-render replaced it). Its
// listeners then retire on the next event they see, without touching `open`,
// whose session may be gone with the node.

class Overlay {
    constructor(root, open, openClass) {
        this.root = root;
        this.open = open;
        this.openClass = openClass;
        this.dismiss = null;
        open.on(value => { this.show(value); });
        this.show(open.value);
    }

    // Register the document listeners of one open.
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

    // False once the overlay has left the page, after dropping its listeners.
    alive() {
        if (this.root.isConnected) return true;
        if (this.dismiss) { this.dismiss.abort(); this.dismiss = null; }
        return false;
    }

    close() {
        if (this.alive()) this.open.notify(false);
    }
}

export class Menu extends Overlay {
    constructor(root, trigger, list, open, closeOnPick) {
        super(root, open, 'bw-menu-open');
        trigger.addEventListener('click', event => {
            event.stopPropagation();
            open.notify(!open.value);
        });
        // Bubbling, so the item's own handler has run when the menu closes.
        if (closeOnPick) list.addEventListener('click', event => {
            if (event.target.closest('.bw-menu-item')) open.notify(false);
        });
    }

    listen(signal) {
        // Capture, so a click that something else stops still closes the menu.
        // The click itself goes on to its target.
        document.addEventListener('click', event => {
            if (!this.root.contains(event.target)) this.close();
        }, { capture: true, signal });
        document.addEventListener('keydown', event => {
            if (event.key === 'Escape') this.close();
        }, { capture: true, signal });
    }
}

export class Modal extends Overlay {
    constructor(overlay, closeButton, open) {
        super(overlay, open, 'bw-modal-open');
        closeButton.addEventListener('click', () => open.notify(false));
        // Only a click that starts AND ends on the backdrop closes: selecting
        // text in a field and releasing outside the card must not.
        let downOnBackdrop = false;
        overlay.addEventListener('pointerdown', event => {
            downOnBackdrop = event.target === overlay;
        });
        overlay.addEventListener('click', event => {
            if (downOnBackdrop && event.target === overlay) open.notify(false);
            downOnBackdrop = false;
        });
    }

    listen(signal) {
        document.addEventListener('keydown', event => {
            if (event.key !== 'Escape') return;
            event.stopPropagation();
            this.close();
        }, { capture: true, signal });
    }
}
