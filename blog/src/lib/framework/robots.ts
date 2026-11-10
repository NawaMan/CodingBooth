// Prerendered robots.txt — see sitemap.xml/+server.ts for why a prerendered
// endpoint is static-host safe (build-time file, no runtime server). The Sitemap:
// line is an absolute URL, so it is only emitted when a base URL is configured.
import { SITE_URL, absoluteUrl } from '$lib/seo/config';

export const prerender = true;

export function GET() {
	const lines = ['User-agent: *', 'Allow: /'];
	if (SITE_URL) lines.push(`Sitemap: ${absoluteUrl('/sitemap.xml')}`);
	return new Response(lines.join('\n') + '\n', {
		headers: { 'content-type': 'text/plain' }
	});
}
