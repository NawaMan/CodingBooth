// The project's resolved settings, as the plugin injected them (see ./siteConfigCore.ts).
//
// `__GEEKPRESENT_CONFIG__` is replaced at build time by Vite `define` — by the plugin in
// vite.config.ts, and by the test configs for vitest. A module that reads SITE without one
// of those in place throws a bare ReferenceError, which is the signal that the plugin is
// missing from the Vite (or vitest) config.
import type { SiteConfig } from './siteConfigCore';

declare const __GEEKPRESENT_CONFIG__: SiteConfig;

export const SITE: SiteConfig = __GEEKPRESENT_CONFIG__;
