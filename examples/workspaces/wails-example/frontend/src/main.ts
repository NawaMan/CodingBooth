import {Events, WML} from "@wailsio/runtime";
import {Counter} from "../bindings/booth-counter/backend";

WML.Enable();

const countElement = document.getElementById('count')! as HTMLElement;
const incrementButton = document.getElementById('increment')! as HTMLButtonElement;
const resetButton = document.getElementById('reset')! as HTMLButtonElement;
const resultElement = document.getElementById('result')! as HTMLSpanElement;
const timeElement = document.getElementById('time')! as HTMLSpanElement;
const toastElement = document.getElementById('toast')! as HTMLDivElement;
let toastTimer: ReturnType<typeof setTimeout>;

document.getElementById('version')!.innerText = "v3.0.0-beta.16";

function showCount(value: number) {
    countElement.innerText = String(value);
}

function showToast(message: string) {
    resultElement.innerText = message;
    toastElement.classList.add('is-visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastElement.classList.remove('is-visible'), 2500);
}

Counter.Value().then(showCount).catch(console.error);

incrementButton.addEventListener('click', async () => {
    try {
        const value = await Counter.Increment();
        showCount(value);
        showToast(`Go says ${value}`);
    } catch (err) {
        console.error(err);
    }
});

resetButton.addEventListener('click', async () => {
    try {
        const value = await Counter.Reset();
        showCount(value);
        showToast('Go reset to 0');
    } catch (err) {
        console.error(err);
    }
});

Events.On('time', (time) => {
    const full = time.data;
    const compact = (full.match(/\d{1,2}:\d{2}:\d{2}/) || [full])[0];
    timeElement.innerText = window.matchMedia('(max-width: 640px)').matches ? compact : full;
});
