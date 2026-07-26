// Pure key decisions for the `/_source-edit` popup window.
//
// Capture-phase handlers call this so Monaco cannot swallow Esc / armed letters.
// Arm mode (Alt+.) is one-shot per letter: the page disarms after save/refresh/close.
// A second Alt+. while armed cancels without acting.
//
// Total: garbage → 'ignore', never throw.

export type SourceEditKeyIntent = 'arm-toggle' | 'save' | 'refresh' | 'close' | 'ignore';

/** Minimal key fields (real KeyboardEvent or a test stub). */
export type SourceEditKeyEvent = {
	key?: string;
	code?: string;
	altKey?: boolean;
	ctrlKey?: boolean;
	metaKey?: boolean;
	shiftKey?: boolean;
};

function letterOf(e: SourceEditKeyEvent): string {
	const k = (e.key ?? '').toLowerCase();
	if (/^[a-z]$/.test(k)) return k;
	const code = e.code ?? '';
	return /^Key[A-Z]$/.test(code) ? code.slice(3).toLowerCase() : '';
}

/**
 * What a key means in the source-edit window.
 *
 * @param keysArmed  is Alt+.-arm currently live?
 */
export function sourceEditKeyIntent(
	e: SourceEditKeyEvent,
	keysArmed: boolean
): SourceEditKeyIntent {
	const mod = !!(e.ctrlKey || e.metaKey);
	const alt = !!e.altKey;
	const shift = !!e.shiftKey;
	const key = e.key ?? '';
	const code = e.code ?? '';

	// Alt+. — arm or cancel arm (toggle).
	if (alt && !mod && !shift && (code === 'Period' || key === '.')) {
		return 'arm-toggle';
	}

	// Ctrl/Cmd+S — SAVE.
	if (mod && !shift && !alt && (key === 's' || key === 'S' || code === 'KeyS')) {
		return 'save';
	}

	// Ctrl/Cmd+Shift+R — REFRESH (intercept browser hard-reload).
	if (mod && shift && !alt && (key === 'r' || key === 'R' || code === 'KeyR')) {
		return 'refresh';
	}

	// Esc — CLOSE (with dirty confirm in the page).
	if (key === 'Escape' && !mod && !alt) {
		return 'close';
	}

	// While armed: r / s / c (even with caret in Monaco).
	if (keysArmed && !mod && !alt) {
		const L = letterOf(e);
		if (L === 'r') return 'refresh';
		if (L === 's') return 'save';
		if (L === 'c') return 'close';
	}

	return 'ignore';
}
