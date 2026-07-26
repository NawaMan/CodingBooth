import { persisted } from './persisted';
import { numberCodec } from '$lib/utils/stateCore';

/** A diagram's horizontal scroll offset, remembered across a reload.

    This is the store that motivated `persisted()`. It used to read its key with a bare
    `parseInt`, so one corrupt byte made it `NaN` — and a geometry store holding NaN lays
    the diagram out at `NaNpx`. `numberCodec()` is the whole fix: a value that is not a
    finite number reads as `null`, which lands on the initial offset below.

    `sync: false` — a second window scrolling this diagram should not drag THIS window's
    diagram along with it. */
export const diagramScroll = persisted('diagramScroll', -500, {
	codec: numberCodec(),
	sync: false
});
