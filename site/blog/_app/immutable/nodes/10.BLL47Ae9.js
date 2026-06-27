import{s as d,n as p}from"../chunks/CD4XNkCN.js";import{S as v,i as w,d as l,n as g,k as b,l as $,o as _,a as r,p as x,g as S,q as y,j as T,r as c,c as u,m,h}from"../chunks/CiItmipK.js";import{T as P}from"../chunks/BeYW_IjY.js";import{V as C}from"../chunks/g-EYfNB2.js";const k=`<script>
	import TitlePage  from '$lib/templates/TitlePage.svelte';
	import ViewSource from '$lib/components/ViewSource.svelte';
	import source     from './+page.svelte?raw';
<\/script>

<TitlePage>
	<span slot="title">Thanks for stopping by</span>
	<span slot="subtitle">See you in the next post</span>
	<span slot="subsubtitle">
		<a href="../" style="opacity: 0.85;">↑ back to the blog index</a> &nbsp;·&nbsp;
		<a href="https://codingbooth.io" style="opacity: 0.85;">codingbooth.io</a>
	</span>
</TitlePage>

<ViewSource {source} path="src/routes/welcome/thank-you.html/+page.svelte" />
`;function V(i){let t,n="Thanks for stopping by";return{c(){t=h("span"),t.textContent=n,this.h()},l(e){t=u(e,"SPAN",{slot:!0,"data-svelte-h":!0}),m(t)!=="svelte-1mp049w"&&(t.textContent=n),this.h()},h(){c(t,"slot","title")},m(e,o){r(e,t,o)},p,d(e){e&&l(t)}}}function A(i){let t,n="See you in the next post";return{c(){t=h("span"),t.textContent=n,this.h()},l(e){t=u(e,"SPAN",{slot:!0,"data-svelte-h":!0}),m(t)!=="svelte-1fwubju"&&(t.textContent=n),this.h()},h(){c(t,"slot","subtitle")},m(e,o){r(e,t,o)},p,d(e){e&&l(t)}}}function N(i){let t,n=`<a href="../" style="opacity: 0.85;">↑ back to the blog index</a>  · 
		<a href="https://codingbooth.io" style="opacity: 0.85;">codingbooth.io</a>`;return{c(){t=h("span"),t.innerHTML=n,this.h()},l(e){t=u(e,"SPAN",{slot:!0,"data-svelte-h":!0}),m(t)!=="svelte-2gc8ap"&&(t.innerHTML=n),this.h()},h(){c(t,"slot","subsubtitle")},m(e,o){r(e,t,o)},p,d(e){e&&l(t)}}}function j(i){let t,n,e,o;return t=new P({props:{$$slots:{subsubtitle:[N],subtitle:[A],title:[V]},$$scope:{ctx:i}}}),e=new C({props:{source:k,path:"src/routes/welcome/thank-you.html/+page.svelte"}}),{c(){y(t.$$.fragment),n=T(),y(e.$$.fragment)},l(s){x(t.$$.fragment,s),n=S(s),x(e.$$.fragment,s)},m(s,a){_(t,s,a),r(s,n,a),_(e,s,a),o=!0},p(s,[a]){const f={};a&1&&(f.$$scope={dirty:a,ctx:s}),t.$set(f)},i(s){o||($(t.$$.fragment,s),$(e.$$.fragment,s),o=!0)},o(s){b(t.$$.fragment,s),b(e.$$.fragment,s),o=!1},d(s){s&&l(n),g(t,s),g(e,s)}}}class z extends v{constructor(t){super(),w(this,t,null,j,d,{})}}export{z as component};
