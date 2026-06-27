import{s as x,n as p}from"../chunks/CD4XNkCN.js";import{S as w,i as C,d as l,n as g,k as $,l as b,o as _,a as r,p as d,g as T,q as v,j as P,r as c,c as m,m as u,h}from"../chunks/CiItmipK.js";import{T as S}from"../chunks/BeYW_IjY.js";import{V as k}from"../chunks/g-EYfNB2.js";const y=`<script>
	import TitlePage  from '$lib/templates/TitlePage.svelte';
	import ViewSource from '$lib/components/ViewSource.svelte';
	import source     from './+page.svelte?raw';
<\/script>

<TitlePage>
	<span slot="title">The CodingBooth Blog</span>
	<span slot="subtitle">Notes from inside the booth</span>
	<span slot="subsubtitle">Deep dives into the pieces that make CodingBooth tick<br/>
		<a href="../" style="opacity: 0.85;">↑ back to the blog index</a></span>
</TitlePage>

<ViewSource {source} path="src/routes/welcome/title.html/+page.svelte" />
`;function B(i){let t,n="The CodingBooth Blog";return{c(){t=h("span"),t.textContent=n,this.h()},l(e){t=m(e,"SPAN",{slot:!0,"data-svelte-h":!0}),u(t)!=="svelte-z09sbw"&&(t.textContent=n),this.h()},h(){c(t,"slot","title")},m(e,o){r(e,t,o)},p,d(e){e&&l(t)}}}function N(i){let t,n="Notes from inside the booth";return{c(){t=h("span"),t.textContent=n,this.h()},l(e){t=m(e,"SPAN",{slot:!0,"data-svelte-h":!0}),u(t)!=="svelte-gpjz89"&&(t.textContent=n),this.h()},h(){c(t,"slot","subtitle")},m(e,o){r(e,t,o)},p,d(e){e&&l(t)}}}function V(i){let t,n='Deep dives into the pieces that make CodingBooth tick<br/> <a href="../" style="opacity: 0.85;">↑ back to the blog index</a>';return{c(){t=h("span"),t.innerHTML=n,this.h()},l(e){t=m(e,"SPAN",{slot:!0,"data-svelte-h":!0}),u(t)!=="svelte-1gcw55y"&&(t.innerHTML=n),this.h()},h(){c(t,"slot","subsubtitle")},m(e,o){r(e,t,o)},p,d(e){e&&l(t)}}}function A(i){let t,n,e,o;return t=new S({props:{$$slots:{subsubtitle:[V],subtitle:[N],title:[B]},$$scope:{ctx:i}}}),e=new k({props:{source:y,path:"src/routes/welcome/title.html/+page.svelte"}}),{c(){v(t.$$.fragment),n=P(),v(e.$$.fragment)},l(s){d(t.$$.fragment,s),n=T(s),d(e.$$.fragment,s)},m(s,a){_(t,s,a),r(s,n,a),_(e,s,a),o=!0},p(s,[a]){const f={};a&1&&(f.$$scope={dirty:a,ctx:s}),t.$set(f)},i(s){o||(b(t.$$.fragment,s),b(e.$$.fragment,s),o=!0)},o(s){$(t.$$.fragment,s),$(e.$$.fragment,s),o=!1},d(s){s&&l(n),g(t,s),g(e,s)}}}class H extends w{constructor(t){super(),C(this,t,null,A,x,{})}}export{H as component};
