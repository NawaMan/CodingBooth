import{s as v,n as c}from"../chunks/CD4XNkCN.js";import{S as w,i as $,d as l,s as C,A as g,a as m,b as H,r as S,c as _,e as k,f as P,h as x,t as I,n as u,k as p,l as d,o as f,p as h,g as V,q as b,j as y,m as L}from"../chunks/CiItmipK.js";import{C as T}from"../chunks/lfd6-ZqU.js";import{V as j}from"../chunks/g-EYfNB2.js";function A(a){let e,o;return{c(){e=x("div"),o=I(a[0]),this.h()},l(n){e=_(n,"DIV",{class:!0});var i=k(e);o=P(i,a[0]),i.forEach(l),this.h()},h(){S(e,"class","text svelte-1lg2xhr"),g(e,"hidden",!a[1])},m(n,i){m(n,e,i),H(e,o)},p(n,[i]){i&1&&C(o,n[0]),i&2&&g(e,"hidden",!n[1])},i:c,o:c,d(n){n&&l(e)}}}function U(a,e,o){let{text:n="-hint-"}=e,{isVisible:i=!0}=e;return a.$$set=t=>{"text"in t&&o(0,n=t.text),"isVisible"in t&&o(1,i=t.isVisible)},[n,i]}class q extends w{constructor(e){super(),$(this,e,U,A,v,{text:0,isVisible:1})}}const B=`<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import Hint        from '$lib/components/Hint.svelte';
	import ViewSource  from '$lib/components/ViewSource.svelte';
	import source      from './+page.svelte?raw';
<\/script>

<ContentPage title="What's coming" subtitle="Bits and pieces, one post at a time">
	<ul>
		<li><b>Reproducible by design</b> — how a project's whole environment travels with it in a <code>.booth/</code> folder.</li>
		<li><b>Variants</b> — a browser terminal, VS Code, Jupyter, or a full Linux desktop, all over the same environment.</li>
		<li><b>Isolation</b> — egress allow-listing and kernel-level sandboxing for running untrusted or AI-driven code.</li>
		<li><b>Templates &amp; recipes</b> — scaffolding a whole stack from one selection string.</li>
		<li><b>Under the hood</b> — the wrapper, the binary, and how your host identity maps inside the booth.</li>
	</ul>
	<Hint text="Have something you want covered? Open an issue on GitHub." />
</ContentPage>

<ViewSource {source} path="src/routes/welcome/whats-coming.html/+page.svelte" />
`;function G(a){let e,o="<li><b>Reproducible by design</b> — how a project&#39;s whole environment travels with it in a <code>.booth/</code> folder.</li> <li><b>Variants</b> — a browser terminal, VS Code, Jupyter, or a full Linux desktop, all over the same environment.</li> <li><b>Isolation</b> — egress allow-listing and kernel-level sandboxing for running untrusted or AI-driven code.</li> <li><b>Templates &amp; recipes</b> — scaffolding a whole stack from one selection string.</li> <li><b>Under the hood</b> — the wrapper, the binary, and how your host identity maps inside the booth.</li>",n,i,t;return i=new q({props:{text:"Have something you want covered? Open an issue on GitHub."}}),{c(){e=x("ul"),e.innerHTML=o,n=y(),b(i.$$.fragment)},l(s){e=_(s,"UL",{"data-svelte-h":!0}),L(e)!=="svelte-2edt6d"&&(e.innerHTML=o),n=V(s),h(i.$$.fragment,s)},m(s,r){m(s,e,r),m(s,n,r),f(i,s,r),t=!0},p:c,i(s){t||(d(i.$$.fragment,s),t=!0)},o(s){p(i.$$.fragment,s),t=!1},d(s){s&&(l(e),l(n)),u(i,s)}}}function J(a){let e,o,n,i;return e=new T({props:{title:"What's coming",subtitle:"Bits and pieces, one post at a time",$$slots:{default:[G]},$$scope:{ctx:a}}}),n=new j({props:{source:B,path:"src/routes/welcome/whats-coming.html/+page.svelte"}}),{c(){b(e.$$.fragment),o=y(),b(n.$$.fragment)},l(t){h(e.$$.fragment,t),o=V(t),h(n.$$.fragment,t)},m(t,s){f(e,t,s),m(t,o,s),f(n,t,s),i=!0},p(t,[s]){const r={};s&1&&(r.$$scope={dirty:s,ctx:t}),e.$set(r)},i(t){i||(d(e.$$.fragment,t),d(n.$$.fragment,t),i=!0)},o(t){p(e.$$.fragment,t),p(n.$$.fragment,t),i=!1},d(t){t&&l(o),u(e,t),u(n,t)}}}class D extends w{constructor(e){super(),$(this,e,null,J,v,{})}}export{D as component};
