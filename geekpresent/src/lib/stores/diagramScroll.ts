import { writable } from 'svelte/store';
import { browser } from '$app/environment';

let initialDiagramScroll = -500;

if (browser) {
    const storedDiagramScroll = localStorage.getItem('diagramScroll');
    if (storedDiagramScroll !== null) {
        initialDiagramScroll = parseInt(storedDiagramScroll);
    } else {
        localStorage.setItem('diagramScroll', '-500');
    }
}

export const diagramScroll = writable(initialDiagramScroll);

if (browser) {
    diagramScroll.subscribe((value) => {
        localStorage.setItem('diagramScroll', value.toString());
    });
}
