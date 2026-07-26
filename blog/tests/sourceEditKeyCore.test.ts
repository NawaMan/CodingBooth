import { describe, expect, it } from 'vitest';
import { sourceEditKeyIntent } from '../src/lib/source/sourceEditKeyCore';

function key(
	partial: Partial<{
		key: string;
		code: string;
		altKey: boolean;
		ctrlKey: boolean;
		metaKey: boolean;
		shiftKey: boolean;
	}>
) {
	return {
		key: partial.key ?? '',
		code: partial.code ?? '',
		altKey: !!partial.altKey,
		ctrlKey: !!partial.ctrlKey,
		metaKey: !!partial.metaKey,
		shiftKey: !!partial.shiftKey
	};
}

describe('sourceEditKeyIntent', () => {
	it('Alt+. toggles arm (same key whether armed or not — page decides toggle)', () => {
		expect(sourceEditKeyIntent(key({ key: '.', code: 'Period', altKey: true }), false)).toBe(
			'arm-toggle'
		);
		expect(sourceEditKeyIntent(key({ key: '.', code: 'Period', altKey: true }), true)).toBe(
			'arm-toggle'
		);
	});

	it('maps Ctrl/Cmd+S to save and Ctrl/Cmd+Shift+R to refresh', () => {
		expect(sourceEditKeyIntent(key({ key: 's', ctrlKey: true }), false)).toBe('save');
		expect(sourceEditKeyIntent(key({ key: 's', metaKey: true }), false)).toBe('save');
		expect(sourceEditKeyIntent(key({ key: 'r', ctrlKey: true, shiftKey: true }), false)).toBe(
			'refresh'
		);
		expect(sourceEditKeyIntent(key({ key: 'R', metaKey: true, shiftKey: true }), false)).toBe(
			'refresh'
		);
	});

	it('maps Escape to close (even when not armed)', () => {
		expect(sourceEditKeyIntent(key({ key: 'Escape' }), false)).toBe('close');
		expect(sourceEditKeyIntent(key({ key: 'Escape' }), true)).toBe('close');
	});

	it('while armed, r/s/c fire refresh/save/close', () => {
		expect(sourceEditKeyIntent(key({ key: 'r' }), true)).toBe('refresh');
		expect(sourceEditKeyIntent(key({ key: 's' }), true)).toBe('save');
		expect(sourceEditKeyIntent(key({ key: 'c' }), true)).toBe('close');
		expect(sourceEditKeyIntent(key({ key: 'C' }), true)).toBe('close');
	});

	it('while unarmed, bare r/s/c are ignore (so typing in Monaco is safe)', () => {
		expect(sourceEditKeyIntent(key({ key: 'r' }), false)).toBe('ignore');
		expect(sourceEditKeyIntent(key({ key: 's' }), false)).toBe('ignore');
		expect(sourceEditKeyIntent(key({ key: 'c' }), false)).toBe('ignore');
	});

	it('falls back to physical key on non-Latin layouts while armed', () => {
		expect(sourceEditKeyIntent(key({ key: 'ы', code: 'KeyS' }), true)).toBe('save');
		expect(sourceEditKeyIntent(key({ key: 'с', code: 'KeyC' }), true)).toBe('close');
	});

	it('is total on garbage', () => {
		expect(sourceEditKeyIntent(key({}), false)).toBe('ignore');
		expect(sourceEditKeyIntent(key({ key: '', code: '' }), true)).toBe('ignore');
	});
});
