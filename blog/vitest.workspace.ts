// Two test projects: 'dom' (jsdom + testing-library, the component/unit
// suite) and 'ssr' (node, server-compiled components for prerender checks).
// `vitest run` / `pnpm test` runs both.
export default ['./vitest.config.ts', './vitest.ssr.config.ts'];
