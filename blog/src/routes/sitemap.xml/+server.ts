// Prerendered sitemap endpoint — NOT a runtime server route.
//
// adapter-static evaluates this once at BUILD time and writes the result to
// `sitemap.xml` in the output, exactly like a prerendered page. So it is fully
// compatible with GitHub Pages / any static host: there is no server at runtime.
// (AGENTS.md's "no +server.js" rule is about RUNTIME endpoints, which can't run on
// Pages; a prerendered GET endpoint is just a build-time file generator and is the
// idiomatic SvelteKit way to emit sitemap.xml / robots.txt.)
//
// URLs are absolute (search engines require it), built from the base URL. With no
// base URL configured the sitemap has no resolvable URLs, so we emit a valid but
// empty <urlset> rather than relative/broken entries.
import { SITE_URL, absoluteUrl } from '$lib/seo/config';
import { siteRoutes } from '$lib/seo/routes';

export const prerender = true;

export function GET() {
	const urls = SITE_URL ? siteRoutes().map((r) => absoluteUrl(r)) : [];
	const body =
		`<?xml version="1.0" encoding="UTF-8"?>\n` +
		`<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
		urls.map((u) => `\t<url><loc>${u}</loc></url>`).join('\n') +
		(urls.length ? '\n' : '') +
		`</urlset>\n`;
	return new Response(body, {
		headers: { 'content-type': 'application/xml' }
	});
}
