<!--
  Gantt — tasks as SPANS on a time axis: one lane per task, each bar running from
  its start to its end, with dependency arrows between them. The roadmap /
  migration-plan / pipeline-stage slide.

  This is the family's one chart whose mark has a LENGTH. Every other chart plots
  a point value — one number per category or per x — so a phase that "runs from
  week 2 to week 6, overlapping the next one" had nowhere to live. `Timeline` (the
  CSS event spine) is deliberately not this: its events are evenly spaced markers
  with free-text labels and no date arithmetic, so an event cannot express a
  length and two events three years apart sit as far apart as two three days apart.

    • spans — start → end, from real dates (Date / ISO string / timestamp). A
      reversed pair is normalised rather than drawn inside-out.
    • milestones — a row with no end is a MOMENT, drawn as a diamond, never an
      open-ended bar running off the axis.
    • progress — an optional fraction (or percentage) shading part of the bar.
    • dependsOn — FINISH-TO-START arrows from a predecessor's end to its
      dependent's start, declared by TASK NAME and resolved by value, so
      reordering rows can't silently repoint an arrow. An edge naming a task that
      doesn't exist is dropped, not drawn to the wrong bar. One link type is
      modelled; start-to-start / finish-to-finish and lag are not.
    • A dependent that starts BEFORE its predecessor finishes contradicts the
      only relationship this chart can express, so the arrow would run backwards
      in time. Those links are drawn DASHED in the warn colour with a `<title>`
      saying why, rather than passed off as ordinary. The plan is drawn as given
      — only the author knows whether the dates or the dependency is wrong.
    • today — an optional "you are here" rule.
    • A row with no usable start keeps its LANE (so the task still appears on the
      axis) but draws no bar — the same call waterfallBars makes for a blank.

  Wiring + SVG only; all math is pure in chartCore.ts, flowing through the
  chained pipeline (each stage its own $derived, never merged):

      data → gantt bars + links → time-x + band-y scales → rects/elbows → SVG

  The time axis reuses the machinery LineChart/AreaChart/ScatterChart already
  use: a linearScale over epoch ms (nice:false) with calendar-aware timeTicks.

  SSR-safe: the full <svg> — bars, milestones, arrows, axes — renders from props
  alone; the hover tooltip and the draw-in wipe are client-only enhancements.
  Accessible: role="img" with a required `title` (→ <title>), optional
  `description` (→ <desc>), and one aria-label per bar carrying its span and
  duration ("Migrate schema: Mar 3 – Mar 17 (14 days)").
  Theme via --chart-task / --chart-task-done / --chart-milestone / --chart-link /
  --chart-today and the shared --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import {
		bandScale,
		ganttBars,
		ganttExtent,
		ganttLinks,
		linearScale,
		nearestIndex,
		timeTicks,
		toTime,
		type GanttBar
	} from './chartCore';
	import type { Accessor, TooltipPoint } from './types';

	interface Props {
		data: T[];
		/** The lane label — one band per row, in the order given. */
		task: Accessor<T>;
		/** Span start (Date / ISO string / ms). */
		start: Accessor<T>;
		/** Span end; a blank makes the row a milestone at `start`. */
		end: Accessor<T>;
		/** Fraction complete (0–1, or 0–100 — both work). Optional. */
		progress?: Accessor<T>;
		/** A predecessor task name, or an array of them, matched by value. */
		dependsOn?: Accessor<T>;
		/** Draw a "you are here" rule at this date. */
		today?: Date | string | number;
		/** Override date text in ticks, tooltips and aria-labels. */
		dateFormat?: (value: Date) => string;
		/** Tick-count hint for the time axis. */
		ticks?: number;
		/** Label under the time axis. */
		xLabel?: string;
		/** Bar thickness as a fraction of its lane. */
		barHeight?: number;
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** Play a one-off left-to-right draw-in when the chart mounts (client-only,
		 *  skipped under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (task, points, row). */
		tooltip?: Snippet<[unknown, TooltipPoint[], T]>;
	}

	let {
		data,
		task,
		start,
		end,
		progress,
		dependsOn,
		today,
		dateFormat,
		ticks = 6,
		xLabel,
		barHeight = 0.62,
		width = 640,
		height = 400,
		title,
		description,
		animate = false,
		tooltip
	}: Props = $props();

	// The plan: pure span math from the core (one bar per row, lanes in order).
	const bars = $derived(ganttBars(data, { task, start, end, progress }));
	const links = $derived(dependsOn ? ganttLinks(data, bars, dependsOn) : []);

	// Lane labels need room; the left margin scales with the longest one so a
	// task name isn't clipped by a fixed inset.
	const laneLabelWidth = $derived(
		Math.min(220, Math.max(60, ...bars.map((b) => String(b.task ?? '').length * 7 + 16)))
	);
	const margin = $derived({
		top: 18,
		right: 24, // room for an arrow entering the last bar
		bottom: 40 + (xLabel ? 22 : 0),
		left: laneLabelWidth
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	// x: epoch ms on a linear scale, nice:false so the domain stays the real span
	// (the LineChart time-axis pattern); ticks come from the calendar ladder.
	const xScale = $derived(
		linearScale(ganttExtent(bars), [plot.left, plot.right], { nice: false })
	);
	const timeT = $derived(timeTicks(xScale.domain[0], xScale.domain[1], ticks));
	const xAxisScale = $derived({ map: xScale.map, ticks: timeT.ticks, domain: xScale.domain });
	const fmtDate = (ms: number): string =>
		dateFormat ? dateFormat(new Date(ms)) : timeT.format(ms);
	const xTickText = (v: unknown): string => fmtDate(v as number);

	// y: one band per lane, top to bottom in the order the rows came.
	const yScale = $derived(
		bandScale(
			bars.map((b) => b.task),
			[plot.top, plot.bottom],
			{ paddingInner: 0.28, paddingOuter: 0.14 }
		)
	);
	const laneY = (bar: GanttBar): number => yScale.map(bar.task);
	const laneCenter = (bar: GanttBar): number => laneY(bar) + yScale.bandwidth / 2;
	const thickness = $derived(
		yScale.bandwidth * Math.min(1, Math.max(0.1, barHeight))
	);

	const DAY_MS = 86400000;
	const HOUR_MS = 3600000;
	const plural = (n: number, unit: string): string => `${n} ${unit}${n === 1 ? '' : 's'}`;
	// Duration reads in the largest unit that isn't a fraction — a plan speaks in
	// days or weeks, not 1209600000.
	const durationText = (ms: number): string => {
		if (!Number.isFinite(ms) || ms <= 0) return '0 days';
		if (ms < HOUR_MS) return plural(Math.max(1, Math.round(ms / 60000)), 'minute');
		if (ms < DAY_MS) return plural(Math.round(ms / HOUR_MS), 'hour');
		return plural(Math.round(ms / DAY_MS), 'day');
	};

	const taskLabel = (t: unknown): string => (t === null || t === undefined ? '' : String(t));
	const ariaLabel = (bar: GanttBar): string => {
		const name = taskLabel(bar.task);
		if (bar.blank) return `${name}: no dates`;
		if (bar.milestone) return `${name}: ${fmtDate(bar.t0)} (milestone)`;
		const base = `${name}: ${fmtDate(bar.t0)} – ${fmtDate(bar.t1)} (${durationText(bar.duration)})`;
		return bar.progress > 0 ? `${base}, ${Math.round(bar.progress * 100)}% complete` : base;
	};

	interface Span {
		key: string;
		x: number;
		y: number;
		width: number;
		height: number;
		doneWidth: number; // the progress overlay's width (0 when absent)
		label: string;
	}
	interface Diamond {
		key: string;
		cx: number;
		cy: number;
		r: number;
		label: string;
	}

	// Placeable spans become rects; milestones become diamonds. A blank row is
	// neither — its lane (and axis label) survives, but nothing is drawn.
	const spans = $derived.by<Span[]>(() => {
		const out: Span[] = [];
		for (const bar of bars) {
			if (bar.blank || bar.milestone) continue;
			const x0 = xScale.map(bar.t0);
			const x1 = xScale.map(bar.t1);
			const y = laneCenter(bar) - thickness / 2;
			if (![x0, x1, y].every(Number.isFinite)) continue;
			const w = Math.max(1, x1 - x0); // a same-day span still shows
			out.push({
				key: bar.key,
				x: x0,
				y,
				width: w,
				height: thickness,
				doneWidth: w * bar.progress,
				label: ariaLabel(bar)
			});
		}
		return out;
	});

	const diamonds = $derived.by<Diamond[]>(() => {
		const out: Diamond[] = [];
		for (const bar of bars) {
			if (bar.blank || !bar.milestone) continue;
			const cx = xScale.map(bar.t0);
			const cy = laneCenter(bar);
			if (!Number.isFinite(cx) || !Number.isFinite(cy)) continue;
			out.push({ key: bar.key, cx, cy, r: thickness * 0.5, label: ariaLabel(bar) });
		}
		return out;
	});

	// Dependency arrows: an elbow from the predecessor's end to the dependent's
	// start. When the dependent starts BEFORE that end (an overlap), the route
	// detours through the gap between the two lanes instead of doubling back
	// through the bars.
	const STUB = 10;
	const elbows = $derived.by<{ key: string; d: string; violated: boolean; label: string }[]>(() => {
		const out: { key: string; d: string; violated: boolean; label: string }[] = [];
		for (const link of links) {
			const from = bars[link.from];
			const to = bars[link.to];
			if (!from || !to) continue;
			const x1 = xScale.map(from.t1);
			const x0 = xScale.map(to.t0);
			const yF = laneCenter(from);
			const yT = laneCenter(to);
			if (![x1, x0, yF, yT].every(Number.isFinite)) continue;

			const d =
				x0 - x1 >= 2 * STUB
					? `M ${x1} ${yF} H ${x1 + STUB} V ${yT} H ${x0}`
					: `M ${x1} ${yF} H ${x1 + STUB} V ${(yF + yT) / 2} H ${x0 - STUB} V ${yT} H ${x0}`;
			out.push({
				key: `${link.fromKey}->${link.toKey}`,
				d,
				violated: link.violated,
				label: `${taskLabel(from.task)} → ${taskLabel(to.task)}`
			});
		}
		return out;
	});

	const todayMs = $derived(today === undefined ? NaN : toTime(today));
	const todayX = $derived(Number.isFinite(todayMs) ? xScale.map(todayMs) : NaN);

	// Unique ids: an arrowhead marker and the reveal clip, both scoped per instance
	// so two Gantts on one slide can't collide.
	const uid = Math.random().toString(36).slice(2);
	const markerId = `chart-gantt-arrow-${uid}`;
	// A second arrowhead in the warn colour: a dashed red line ending in a grey
	// head would read as a rendering slip rather than a flagged contradiction.
	const markerWarnId = `chart-gantt-arrow-warn-${uid}`;
	const clipId = `chart-gantt-clip-${uid}`;

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false, so the static SVG is byte-identical with
	// or without JS. The pointer snaps to the nearest LANE (vertical, unlike the
	// bar charts' horizontal snap — here the categories run down the side).
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	let revealed = $state(false);
	let animating = $state(false);
	const clipActive = $derived(animate && mounted && animating);
	const PAD = 32;

	onMount(() => {
		mounted = true;
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
		if (animate && !reduce) {
			animating = true;
			requestAnimationFrame(() => requestAnimationFrame(() => (revealed = true)));
		}
	});

	const laneAnchors = $derived(
		bars
			.map((bar, i) => ({ i, py: laneCenter(bar) }))
			.filter((a) => Number.isFinite(a.py))
			.sort((a, b) => a.py - b.py)
	);

	function onMove(e: PointerEvent) {
		if (!svgEl || laneAnchors.length === 0) return;
		const rect = svgEl.getBoundingClientRect();
		const ly = ((e.clientY - rect.top) / rect.height) * height;
		const k = nearestIndex(
			laneAnchors.map((a) => a.py),
			ly
		);
		hoverIdx = k < 0 ? null : laneAnchors[k].i;
	}
	function onLeave() {
		hoverIdx = null;
	}

	interface Hover {
		leftPct: number;
		topPct: number;
		xValue: unknown;
		xLabel: string;
		points: TooltipPoint[];
		row: T;
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverIdx === null) return null;
		const bar = bars[hoverIdx];
		const row = data[hoverIdx];
		if (!bar || row === undefined || bar.blank) return null;
		const cy = laneCenter(bar);
		const anchorX = Number.isFinite(xScale.map(bar.t1))
			? xScale.map(bar.milestone ? bar.t0 : bar.t1)
			: plot.left;

		const points: TooltipPoint[] = bar.milestone
			? [
					{
						key: 'date',
						label: 'Date',
						value: bar.t0,
						formatted: fmtDate(bar.t0),
						color: 'var(--chart-milestone, #b25f00)'
					}
				]
			: [
					{
						key: 'span',
						label: 'Span',
						value: bar.t0,
						formatted: `${fmtDate(bar.t0)} – ${fmtDate(bar.t1)}`,
						color: 'var(--chart-task, #2f6db0)'
					},
					{
						key: 'duration',
						label: 'Duration',
						value: bar.duration,
						formatted: durationText(bar.duration),
						color: 'var(--chart-task-done, #1f4d80)'
					},
					...(bar.progress > 0
						? [
								{
									key: 'progress',
									label: 'Complete',
									value: bar.progress,
									formatted: `${Math.round(bar.progress * 100)}%`,
									color: 'var(--chart-task-done, #1f4d80)'
								}
							]
						: [])
				];

		return {
			leftPct: (anchorX / width) * 100,
			topPct: (cy / height) * 100,
			xValue: bar.task,
			xLabel: taskLabel(bar.task),
			points,
			row
		};
	});
</script>

<div class="chart-root">
	<div class="plot-wrap">
		<svg
			class="chart"
			viewBox="0 0 {width} {height}"
			role="img"
			aria-label={title}
			preserveAspectRatio="xMidYMid meet"
			bind:this={svgEl}
			onpointermove={onMove}
			onpointerleave={onLeave}
		>
			<title>{title}</title>
			{#if description}<desc>{description}</desc>{/if}

			<defs>
				<marker
					id={markerId}
					viewBox="0 0 8 8"
					refX="7"
					refY="4"
					markerWidth="6"
					markerHeight="6"
					orient="auto-start-reverse"
				>
					<path class="arrowhead" d="M 0 1 L 7 4 L 0 7 z" />
				</marker>
				<marker
					id={markerWarnId}
					viewBox="0 0 8 8"
					refX="7"
					refY="4"
					markerWidth="6"
					markerHeight="6"
					orient="auto-start-reverse"
				>
					<path class="arrowhead warn" d="M 0 1 L 7 4 L 0 7 z" />
				</marker>
			</defs>

			{#if clipActive}
				<clipPath id={clipId}>
					<rect
						class="wipe"
						class:run={revealed}
						x={plot.left - PAD}
						y={plot.top - PAD}
						width={plot.right - plot.left + PAD * 2}
						height={plot.bottom - plot.top + PAD * 2}
						style:transform-origin="{plot.left - PAD}px {(plot.top + plot.bottom) / 2}px"
					/>
				</clipPath>
			{/if}

			<Axis
				orientation="bottom"
				scale={xAxisScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={xTickText}
				gridlines
				label={xLabel}
			/>

			<g class="marks" clip-path={clipActive ? `url(#${clipId})` : undefined}>
				<g class="spans">
					{#each spans as span (span.key)}
						<rect
							class="span"
							x={span.x}
							y={span.y}
							width={span.width}
							height={span.height}
							rx="3"
							aria-label={span.label}
						/>
						{#if span.doneWidth > 0}
							<rect
								class="done"
								x={span.x}
								y={span.y}
								width={span.doneWidth}
								height={span.height}
								rx="3"
								aria-hidden="true"
							/>
						{/if}
					{/each}
				</g>

				<g class="milestones">
					{#each diamonds as dot (dot.key)}
						<path
							class="milestone"
							d="M {dot.cx} {dot.cy - dot.r} L {dot.cx + dot.r} {dot.cy} L {dot.cx} {dot.cy +
								dot.r} L {dot.cx - dot.r} {dot.cy} z"
							aria-label={dot.label}
						/>
					{/each}
				</g>

				<g class="links">
					{#each elbows as elbow (elbow.key)}
						<path
							class="link"
							class:violated={elbow.violated}
							d={elbow.d}
							marker-end="url(#{elbow.violated ? markerWarnId : markerId})"
							aria-hidden="true"
						>
							{#if elbow.violated}
								<!-- The one place an arrow explains itself: the dates contradict the
								     dependency, and a dashed line alone doesn't say why. -->
								<title>{elbow.label}: starts before its dependency ends</title>
							{/if}
						</path>
					{/each}
				</g>
			</g>

			{#if Number.isFinite(todayX)}
				<line class="today" x1={todayX} y1={plot.top} x2={todayX} y2={plot.bottom} />
			{/if}

			<Axis
				orientation="left"
				scale={yScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
			/>
		</svg>

		{#if hover}
			<ChartTooltip
				xLabel={hover.xLabel}
				xValue={hover.xValue}
				points={hover.points}
				left={hover.leftPct}
				top={hover.topPct}
				row={hover.row}
				{tooltip}
			/>
		{/if}
	</div>
</div>

<style>
	.chart-root {
		display: block;
		width: 100%;
	}
	.plot-wrap {
		position: relative;
		width: 100%;
	}
	.chart {
		display: block;
		width: 100%;
		height: auto;
		color: var(--chart-fg, currentColor);
		font-size: var(--chart-font-size, 13px);
		font-family: inherit;
		background: var(--chart-bg, transparent);
	}
	.span {
		fill: var(--chart-task, #2f6db0);
	}
	/* The completed part of a bar: same hue, read as "filled in". */
	.done {
		fill: var(--chart-task-done, #1f4d80);
	}
	.milestone {
		fill: var(--chart-milestone, #b25f00);
	}
	/* Arrows are connective tissue, not data — thin, and dimmer than the bars. */
	.link {
		fill: none;
		stroke: var(--chart-link, color-mix(in srgb, currentColor 45%, transparent));
		stroke-width: 1.25;
	}
	/* A link the dates contradict: the dependent starts before this one ends, so
	   the arrow necessarily runs backwards in time. Dashed and warned rather than
	   drawn as though it were a normal finish-to-start. */
	.link.violated {
		stroke: var(--chart-link-warn, #a8342f);
		stroke-dasharray: 4 3;
	}
	.arrowhead {
		fill: var(--chart-link, color-mix(in srgb, currentColor 45%, transparent));
	}
	.arrowhead.warn {
		fill: var(--chart-link-warn, #a8342f);
	}
	.today {
		stroke: var(--chart-today, #b23b3b);
		stroke-width: 1.5;
		stroke-dasharray: 5 3;
	}
	/* Draw-in reveal: the clip rect scales from the left edge of the plot box. */
	.wipe {
		transform-box: view-box;
		transform: scaleX(0);
	}
	.wipe.run {
		transform: scaleX(1);
		transition: transform var(--chart-animate-ms, 850ms) cubic-bezier(0.22, 1, 0.36, 1);
	}
	@media (prefers-reduced-motion: reduce) {
		.wipe {
			transform: none;
		}
	}
</style>
