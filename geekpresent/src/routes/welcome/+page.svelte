<!-- Post index: redirect to the first slide. Presentation-agnostic. -->
<script>
	if (typeof window !== 'undefined') {
		window.location.href = (window.location.pathname + '/title.html').replaceAll('//', '/');
	}
</script>

<div>
	<h1>This page will redirect. Click <a href="title.html">here</a> if it does not.</h1>
</div>
