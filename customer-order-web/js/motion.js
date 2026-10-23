import { animate } from 'motion/mini';

const activeAnimations = new WeakMap();

// Keep rapid interactions on the latest state instead of queueing effects.
export function fadeContent(element) {
    if (!element) return;
    activeAnimations.get(element)?.cancel();
    activeAnimations.delete(element);
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const controls = animate(element, { opacity: [0.8, 1] }, {
        duration: 0.18,
        ease: 'easeOut',
    });
    activeAnimations.set(element, controls);
}
