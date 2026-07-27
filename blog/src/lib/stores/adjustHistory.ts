import { browser } from '$app/environment';

// A tiny shared undo/redo stack for ADJUST-mode drags. Each committed Block
// gesture records a command — a pair of closures that restore the element's
// geometry to before / after the drag. Undo/redo is GLOBAL across every Block
// on the page (you drag several, then Ctrl+Z walks back through all of them), so
// it lives in one module rather than per-component state.
//
// Keyboard: Ctrl/Cmd+Z = undo, Ctrl/Cmd+Shift+Z or Ctrl/Cmd+Y = redo. A single
// window listener is attached once here, so the shortcut fires exactly once per
// press no matter how many Blocks are mounted.
export interface EditCommand {
    undo: () => void;
    redo: () => void;
}

const undoStack: EditCommand[] = [];
const redoStack: EditCommand[] = [];

/** Record a freshly-applied change. Clears the redo stack (a new edit forks history). */
export function record(cmd: EditCommand): void {
    undoStack.push(cmd);
    redoStack.length = 0;
}

export function undo(): void {
    const cmd = undoStack.pop();
    if (!cmd) return;
    cmd.undo();
    redoStack.push(cmd);
}

export function redo(): void {
    const cmd = redoStack.pop();
    if (!cmd) return;
    cmd.redo();
    undoStack.push(cmd);
}

function isTyping(el: EventTarget | null): boolean {
    const node = el as HTMLElement | null;
    const tag = node?.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || !!node?.isContentEditable;
}

if (browser) {
    window.addEventListener('keydown', (e) => {
        if (!(e.ctrlKey || e.metaKey) || isTyping(e.target)) return;
        const k = e.key.toLowerCase();
        const wantRedo = k === 'y' || (k === 'z' && e.shiftKey);
        const wantUndo = k === 'z' && !e.shiftKey;
        if (wantRedo && redoStack.length) { e.preventDefault(); redo(); }
        else if (wantUndo && undoStack.length) { e.preventDefault(); undo(); }
    });
}
