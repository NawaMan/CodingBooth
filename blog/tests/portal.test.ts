// The portal action's contract, exercised directly — especially the destroy
// path: a node still portaled at destroy time lives OUTSIDE its component's
// subtree, where Svelte's anchor-range teardown (block close, HMR replacement
// after a SAVE) cannot see it. The action must evict it itself, or the node
// strands in the target and the remounted component doubles up against it.
import { describe, expect, it } from 'vitest';
import { portal } from '$lib/utils/portal';

function setup() {
	const home = document.createElement('div');
	const node = document.createElement('span');
	node.className = 'thing';
	home.appendChild(node);
	const target = document.createElement('div');
	document.body.append(home, target);
	return { home, node, target };
}

describe('portal action', () => {
	it('moves the node to the target and back home when the target goes null', () => {
		const { home, node, target } = setup();
		const action = portal(node, target);
		expect(node.parentElement).toBe(target);

		action.update(null);
		expect(node.parentElement).toBe(home);

		action.update(target);
		expect(node.parentElement).toBe(target);
		home.remove();
		target.remove();
	});

	it('a null target parks the node at its authored position', () => {
		const { home, node, target } = setup();
		const action = portal(node, null);
		expect(node.parentElement).toBe(home);
		action.destroy();
		home.remove();
		target.remove();
	});

	it('destroy EVICTS a still-portaled node from the target', () => {
		const { home, node, target } = setup();
		const action = portal(node, target);
		expect(target.contains(node)).toBe(true);

		action.destroy();
		// Not stranded in the target — the HMR/SAVE duplicate.
		expect(target.contains(node)).toBe(false);
		expect(target.querySelectorAll('.thing')).toHaveLength(0);
		home.remove();
		target.remove();
	});

	it('destroy leaves a parked node alone for Svelte to tear down', () => {
		const { home, node, target } = setup();
		const action = portal(node, null);
		action.destroy();
		// Parked at home, inside the component subtree — Svelte's job to remove.
		expect(node.parentElement).toBe(home);
		home.remove();
		target.remove();
	});
});
