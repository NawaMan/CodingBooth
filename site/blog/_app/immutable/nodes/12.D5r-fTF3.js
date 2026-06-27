import{s as k,n as x}from"../chunks/CD4XNkCN.js";import{S as P,i as S,d as l,n as $,k as v,l as _,o as b,a as p,p as y,g,q as C,j as d,c as u,m as h,h as f}from"../chunks/CiItmipK.js";import{C as T}from"../chunks/lfd6-ZqU.js";import{V}from"../chunks/g-EYfNB2.js";const j=`<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import ViewSource  from '$lib/components/ViewSource.svelte';
	import source      from './+page.svelte?raw';
<\/script>

<ContentPage title="Welcome 👋" subtitle="What this blog is">
	<p>
		This is the home for short, focused write-ups about <b>CodingBooth</b> — the tool that
		delivers fully reproducible, isolated development environments in a Docker container that
		runs as <i>you</i>, with your files staying yours on the host.
	</p>
	<p>
		Rather than one giant manual, the blog takes it one piece at a time: a single feature, a
		design decision, or a workflow per post — each authored as a slide deck you can click
		through, or a long-form page you can read at your own pace.
	</p>
	<p>
		New posts land here over time. This first one is just the welcome mat.
	</p>
</ContentPage>

<ViewSource {source} path="src/routes/welcome/what-this-is.html/+page.svelte" />
`;function W(m){let e,r=`This is the home for short, focused write-ups about <b>CodingBooth</b> — the tool that
		delivers fully reproducible, isolated development environments in a Docker container that
		runs as <i>you</i>, with your files staying yours on the host.`,n,s,t=`Rather than one giant manual, the blog takes it one piece at a time: a single feature, a
		design decision, or a workflow per post — each authored as a slide deck you can click
		through, or a long-form page you can read at your own pace.`,a,i,w="New posts land here over time. This first one is just the welcome mat.";return{c(){e=f("p"),e.innerHTML=r,n=d(),s=f("p"),s.textContent=t,a=d(),i=f("p"),i.textContent=w},l(o){e=u(o,"P",{"data-svelte-h":!0}),h(e)!=="svelte-dtr2pe"&&(e.innerHTML=r),n=g(o),s=u(o,"P",{"data-svelte-h":!0}),h(s)!=="svelte-smf4m6"&&(s.textContent=t),a=g(o),i=u(o,"P",{"data-svelte-h":!0}),h(i)!=="svelte-sq6ajb"&&(i.textContent=w)},m(o,c){p(o,e,c),p(o,n,c),p(o,s,c),p(o,a,c),p(o,i,c)},p:x,d(o){o&&(l(e),l(n),l(s),l(a),l(i))}}}function q(m){let e,r,n,s;return e=new T({props:{title:"Welcome 👋",subtitle:"What this blog is",$$slots:{default:[W]},$$scope:{ctx:m}}}),n=new V({props:{source:j,path:"src/routes/welcome/what-this-is.html/+page.svelte"}}),{c(){C(e.$$.fragment),r=d(),C(n.$$.fragment)},l(t){y(e.$$.fragment,t),r=g(t),y(n.$$.fragment,t)},m(t,a){b(e,t,a),p(t,r,a),b(n,t,a),s=!0},p(t,[a]){const i={};a&1&&(i.$$scope={dirty:a,ctx:t}),e.$set(i)},i(t){s||(_(e.$$.fragment,t),_(n.$$.fragment,t),s=!0)},o(t){v(e.$$.fragment,t),v(n.$$.fragment,t),s=!1},d(t){t&&l(r),$(e,t),$(n,t)}}}class M extends P{constructor(e){super(),S(this,e,null,q,k,{})}}export{M as component};
