// @vitest-environment node
//
// True server-side render of Connector (svelte/server, no DOM). This is the
// load-bearing test for the whole feature: a Connector resolves its endpoints
// through the module-level anchor registry that named Blocks publish to, and
// that lookup has to happen during SSR — otherwise every prerendered slide
// would ship its diagram with the boxes but no arrows.
import { render } from 'svelte/server';
import { beforeEach, describe, expect, it } from 'vitest';
import { blockAnchors } from '../src/lib/stores/blockAnchors';
import Connector from '../src/lib/components/Connector.svelte';
import ConnectorSsrHost from './ConnectorSsrHost.svelte';

// The registry is module state and there is no onDestroy on the server, so
// names survive between renders (see blockAnchors.ts). Reset it per test so
// each one states its own preconditions.
beforeEach(() => blockAnchors.set(new Map()));

describe('Connector (SSR)', () => {
	it('renders a shaft between two named Blocks that precede it', () => {
		const { body } = render(ConnectorSsrHost, { props: {} });
		// api: 100..300 x 100..200, db: 500..700 — level, so the shaft runs along
		// y=150 from one facing border to the other, pulled back behind the head.
		expect(body).toContain('d="M 300 150 L 484 150"');
		// The arrowhead's tip lands exactly on db's left border.
		expect(body).toContain('<polygon points="500,150');
	});

	it('renders nothing when an endpoint name is unknown', () => {
		const { body } = render(ConnectorSsrHost, { props: { missing: true } });
		expect(body).not.toContain('connector-surface');
		expect(body).not.toContain('<path');
	});

	it('routes ortho as a right-angled path and curve as a cubic', () => {
		const ortho = render(ConnectorSsrHost, { props: { route: 'ortho' } });
		expect(ortho.body).toContain('d="M 300 150 L');

		const curve = render(ConnectorSsrHost, { props: { route: 'curve' } });
		expect(curve.body).toMatch(/d="M 300 150 C /);
	});

	it('draws the visible label as SVG text', () => {
		const { body } = render(ConnectorSsrHost, { props: { label: 'query' } });
		expect(body).toContain('>query</text>');
		// ...and uses it as the accessible name.
		expect(body).toContain('aria-label="query"');
	});

	it('self-hosts a pointer-transparent overlay at canvas scale', () => {
		const { body } = render(ConnectorSsrHost, { props: {} });
		expect(body).toContain('viewBox="0 0 1920 1080"');
		expect(body).toContain('pointer-events:none');
	});

	it('accepts raw points and literal boxes without any Block', () => {
		const { body } = render(Connector, {
			props: { from: [100, 100] as [number, number], to: { x: 400, y: 60, width: 100, height: 80 }, arrow: 'none' }
		});
		expect(body).toContain('d="M 108 100 L 392 100"'); // default gap of 8
		expect(body).not.toContain('<polygon');
	});

	it('names the connection for screen readers when both ends are names', () => {
		const { body } = render(ConnectorSsrHost, { props: {} });
		expect(body).toContain('aria-label="api to db"');
	});
});
