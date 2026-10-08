<!--
  Carte choroplèthe des départements français (métropole + DROM en encarts).
  Fond de carte : @svg-maps/france.departments (CC-BY-4.0, VictorCazanave/svg-maps).

  Deux modes :
    - mode="sequential"  : couleur ∝ `value` (une seule teinte, du clair au foncé, 7 classes par quantiles)
    - mode="categorical" : couleur = `category` (ex. prénom n°1) ; 5 catégories max, le reste en « Autres »
    - mode="locator"     : carte de situation, seul le département `highlight` est coloré

  <FranceMap data={query} code="dpt" value="pour_mille" fmt={(v) => v.toFixed(2) + ' ‰'} />
-->
<script>
	import france from '@svg-maps/france.departments';
	import { QueryLoad } from '@evidence-dev/core-components';

	export let data;
	export let code = 'dpt';
	export let value = 'valeur';
	export let category = undefined;
	export let mode = category ? 'categorical' : 'sequential';
	export let nameCol = 'nom';
	export let title = undefined;
	export let subtitle = undefined;
	export let legendTitle = '';
	export let highlight = undefined;
	export let fmt = (v) => (v == null ? '—' : Number(v).toLocaleString('fr-FR', { maximumFractionDigits: 2 }));
	export let extra = undefined; // (row) => string : ligne supplémentaire dans l'infobulle
	export let height = 460;

	const DROM = [
		{ id: '971', name: 'Guadeloupe' },
		{ id: '972', name: 'Martinique' },
		{ id: '973', name: 'Guyane' },
		{ id: '974', name: 'La Réunion' },
		{ id: '976', name: 'Mayotte' }
	];
	const NAMES = Object.fromEntries([...france.locations.map((l) => [l.id, l.name]), ...DROM.map((d) => [d.id, d.name])]);
	const MAX_CAT = 5;

	let hover = null;
	let mouse = { x: 0, y: 0 };
	let wrap;

	function quantileBreaks(values, n) {
		const v = values.filter((x) => x != null && isFinite(x)).sort((a, b) => a - b);
		if (!v.length) return [];
		const out = [];
		for (let i = 1; i < n; i++) out.push(v[Math.min(v.length - 1, Math.floor((i * v.length) / n))]);
		return [...new Set(out)];
	}

	function build(rows) {
		const byCode = new Map();
		for (const r of rows ?? []) byCode.set(String(r[code]), r);
		let breaks = [];
		let cats = [];
		if (mode === 'categorical') {
			const counts = new Map();
			for (const r of byCode.values()) counts.set(r[category], (counts.get(r[category]) ?? 0) + 1);
			cats = [...counts.entries()]
				.sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0])))
				.slice(0, MAX_CAT)
				.map(([c, n]) => ({ c, n }));
		} else if (mode === 'sequential') {
			breaks = quantileBreaks([...byCode.values()].map((r) => Number(r[value])), 7);
		}
		return { byCode, breaks, cats };
	}

	function fillFor(model, id) {
		const r = model.byCode.get(id);
		if (mode === 'locator') return highlight && String(highlight) === id ? 'var(--fm-cat-1)' : 'var(--fm-empty)';
		if (!r) return 'var(--fm-empty)';
		if (mode === 'categorical') {
			const i = model.cats.findIndex((c) => c.c === r[category]);
			return i >= 0 ? `var(--fm-cat-${i + 1})` : 'var(--fm-other)';
		}
		const v = Number(r[value]);
		if (v == null || !isFinite(v)) return 'var(--fm-empty)';
		let k = 0;
		while (k < model.breaks.length && v >= model.breaks[k]) k++;
		// k ∈ [0, breaks.length] → 7 marches de la rampe
		const step = model.breaks.length ? Math.round((k / model.breaks.length) * 6) + 1 : 4;
		return `var(--fm-seq-${step})`;
	}

	function move(e, id) {
		const b = wrap.getBoundingClientRect();
		mouse = { x: e.clientX - b.left, y: e.clientY - b.top };
		hover = id;
	}
</script>

<div class="fm-root my-4" bind:this={wrap}>
	{#if title}<div class="font-semibold text-sm text-base-content">{title}</div>{/if}
	{#if subtitle}<div class="text-xs text-base-content-muted mb-1">{subtitle}</div>{/if}
	<QueryLoad {data} let:loaded height={height}>
		{@const model = build(Array.from(loaded ?? []))}
		<div class="relative">
			<svg viewBox="0 0 613 650" style="max-height:{height}px" class="w-full" role="img" aria-label={title ?? 'Carte des départements'}>
				{#each france.locations as loc (loc.id)}
					<path
						d={loc.path}
						fill={fillFor(model, loc.id)}
						class="fm-dep"
						class:fm-hl={highlight && String(highlight) === loc.id}
						class:fm-hover={hover === loc.id}
						on:mousemove={(e) => move(e, loc.id)}
						on:mouseleave={() => (hover = null)}
						role="presentation"
					/>
				{/each}
				{#each DROM as d, i}
					<g transform="translate({20 + i * 60}, 592)">
						<rect
							width="44" height="34" rx="4"
							fill={fillFor(model, d.id)}
							class="fm-dep"
							class:fm-hl={highlight && String(highlight) === d.id}
							class:fm-hover={hover === d.id}
							on:mousemove={(e) => move(e, d.id)}
							on:mouseleave={() => (hover = null)}
							role="presentation"
						/>
						<text x="22" y="48" text-anchor="middle" class="fm-drom-label">{d.id}</text>
					</g>
				{/each}
			</svg>

			{#if hover}
				{@const r = model.byCode.get(hover)}
				<div
					class="fm-tip"
					style="left:{Math.min(mouse.x + 14, (wrap?.clientWidth ?? 400) - 200)}px; top:{mouse.y + 14}px"
				>
					<div class="font-semibold">{r?.[nameCol] ?? NAMES[hover]} <span class="opacity-60">({hover})</span></div>
					{#if mode === 'locator'}
					{:else if !r}
						<div class="opacity-70">Aucune donnée</div>
					{:else if mode === 'categorical'}
						<div>{r[category]}</div>
						<div class="opacity-70">{legendTitle} {fmt(r[value])}</div>
					{:else}
						<div>{legendTitle} <b>{fmt(r[value])}</b></div>
					{/if}
					{#if r && extra}<div class="opacity-70">{extra(r)}</div>{/if}
				</div>
			{/if}
		</div>

		<!-- légende -->
		<div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-base-content-muted mt-1">
			{#if mode === 'categorical'}
				{#each model.cats as c, i}
					<span class="inline-flex items-center gap-1">
						<span class="fm-swatch" style="background:var(--fm-cat-{i + 1})" />{c.c}
						<span class="opacity-60">({c.n})</span>
					</span>
				{/each}
				{#if model.byCode.size > model.cats.reduce((s, c) => s + c.n, 0)}
					<span class="inline-flex items-center gap-1"><span class="fm-swatch" style="background:var(--fm-other)" />Autres</span>
				{/if}
			{:else if mode !== 'locator' && model.breaks.length}
				<span>{legendTitle}</span>
				<span>{fmt(Math.min(...[...model.byCode.values()].map((r) => Number(r[value]))))}</span>
				<span class="inline-flex">
					{#each [1, 2, 3, 4, 5, 6, 7] as s}<span class="fm-ramp" style="background:var(--fm-seq-{s})" />{/each}
				</span>
				<span>{fmt(Math.max(...[...model.byCode.values()].map((r) => Number(r[value]))))}</span>
			{/if}
		</div>
	</QueryLoad>
</div>

<style>
	.fm-root {
		--fm-stroke: #fcfcfb;
		--fm-empty: #e9e8e4;
		--fm-other: #b9b8b2;
		--fm-hl: #0b0b0b;
		/* rampe séquentielle : bleu, du clair au foncé */
		--fm-seq-1: #dbe9fa;
		--fm-seq-2: #b5d2f4;
		--fm-seq-3: #86b5ec;
		--fm-seq-4: #5596e2;
		--fm-seq-5: #2a78d6;
		--fm-seq-6: #1d5dab;
		--fm-seq-7: #13427c;
		/* catégories : 5 premiers créneaux de la palette validée */
		--fm-cat-1: #2a78d6;
		--fm-cat-2: #eb6834;
		--fm-cat-3: #1baf7a;
		--fm-cat-4: #eda100;
		--fm-cat-5: #e87ba4;
	}
	:global(html[data-theme='dark']) .fm-root {
		--fm-stroke: #1a1a19;
		--fm-empty: #2c2c2a;
		--fm-other: #5f5e5a;
		--fm-hl: #ffffff;
		--fm-seq-1: #1c2b40;
		--fm-seq-2: #1f3d63;
		--fm-seq-3: #24548c;
		--fm-seq-4: #2c6cb6;
		--fm-seq-5: #3987e5;
		--fm-seq-6: #6aa7ee;
		--fm-seq-7: #a6cbf6;
		--fm-cat-1: #3987e5;
		--fm-cat-2: #d95926;
		--fm-cat-3: #199e70;
		--fm-cat-4: #c98500;
		--fm-cat-5: #d55181;
	}
	.fm-dep {
		stroke: var(--fm-stroke);
		stroke-width: 0.8;
		cursor: pointer;
		transition: opacity 120ms;
	}
	.fm-dep.fm-hover {
		stroke: var(--fm-hl);
		stroke-width: 1.6;
	}
	.fm-dep.fm-hl {
		stroke: var(--fm-hl);
		stroke-width: 2.4;
	}
	.fm-drom-label {
		font-size: 11px;
		fill: currentColor;
		opacity: 0.6;
	}
	.fm-tip {
		position: absolute;
		pointer-events: none;
		z-index: 20;
		min-width: 150px;
		max-width: 220px;
		padding: 6px 10px;
		border-radius: 6px;
		font-size: 12px;
		line-height: 1.4;
		background: var(--base-100, #fff);
		color: var(--base-content, #111);
		border: 1px solid var(--base-300, #ddd);
		box-shadow: 0 4px 14px rgb(0 0 0 / 0.12);
	}
	.fm-swatch {
		display: inline-block;
		width: 10px;
		height: 10px;
		border-radius: 3px;
	}
	.fm-ramp {
		display: inline-block;
		width: 18px;
		height: 10px;
	}
</style>
