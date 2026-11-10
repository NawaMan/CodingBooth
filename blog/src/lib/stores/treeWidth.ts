import { persisted } from '$lib/stores/persisted';
import { numberCodec } from '$lib/utils/stateCore';
import { TREE_DEFAULT_WIDTH, TREE_MIN_WIDTH } from '$lib/source/treeWidthCore';

/** The EDIT window's file-tree width, in CSS px, as last dragged. Remembered across
    windows and reloads; not synced live — one EDIT window dragging its divider has no
    business moving another's. Clamp it against the window with `clampTreeWidth`. */
export const treeWidth = persisted('geekpresent:sourceEdit:treeWidth', TREE_DEFAULT_WIDTH, {
	codec: numberCodec({ min: TREE_MIN_WIDTH, max: 4000 }),
	sync: false
});
