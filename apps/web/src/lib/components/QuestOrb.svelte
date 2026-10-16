<script lang="ts">
	import { onMount } from 'svelte';

	let canvas: HTMLCanvasElement;
	let failed = $state(false);
	let paused = $state(false);

	onMount(() => {
		let disposed = false;
		let animationFrame = 0;
		let renderer: import('three').WebGLRenderer | undefined;
		let scene: import('three').Scene | undefined;
		let camera: import('three').PerspectiveCamera | undefined;
		let constellation: import('three').Group | undefined;
		let resizeObserver: ResizeObserver | undefined;
		let intersectionObserver: IntersectionObserver | undefined;
		const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
		let isVisible = true;

		const render = () => {
			if (!renderer || !scene || !camera || !constellation || disposed) return;

			if (!reduceMotion.matches && !paused && isVisible) {
				constellation.rotation.y += 0.003;
				constellation.rotation.x = Math.sin(performance.now() * 0.0003) * 0.045;
				animationFrame = requestAnimationFrame(render);
			}
			renderer.render(scene, camera);
		};

		const handleMotionChange = () => {
			cancelAnimationFrame(animationFrame);
			render();
		};

		void import('three')
			.then((THREE) => {
				if (disposed) return;

				try {
					renderer = new THREE.WebGLRenderer({
						canvas,
						alpha: true,
						antialias: true,
						powerPreference: 'low-power'
					});
					renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
					renderer.outputColorSpace = THREE.SRGBColorSpace;
					renderer.setClearColor(0x000000, 0);

					scene = new THREE.Scene();
					camera = new THREE.PerspectiveCamera(32, 1, 0.1, 50);
					camera.position.z = 7.2;
					constellation = new THREE.Group();
					scene.add(constellation);

					const core = new THREE.Mesh(
						new THREE.IcosahedronGeometry(1.03, 2),
						new THREE.MeshStandardMaterial({
							color: 0xc8a061,
							metalness: 0.72,
							roughness: 0.25,
							flatShading: true
						})
					);
					constellation.add(core);

					const halo = new THREE.Mesh(
						new THREE.TorusGeometry(1.62, 0.018, 8, 120),
						new THREE.MeshBasicMaterial({ color: 0xe5c58c, transparent: true, opacity: 0.85 })
					);
					halo.rotation.set(0.95, 0.15, 0.18);
					constellation.add(halo);

					const orbit = new THREE.Group();
					orbit.rotation.set(-0.4, 0.6, 0.3);
					constellation.add(orbit);
					const satellites = [
						{ geometry: new THREE.OctahedronGeometry(0.18), color: 0xf2d29b, angle: 0.6 },
						{ geometry: new THREE.IcosahedronGeometry(0.13, 0), color: 0x8c9fdb, angle: 2.7 },
						{ geometry: new THREE.OctahedronGeometry(0.1), color: 0xffffff, angle: 4.55 }
					];

					for (const satellite of satellites) {
						const token = new THREE.Mesh(
							satellite.geometry,
							new THREE.MeshStandardMaterial({
								color: satellite.color,
								metalness: 0.35,
								roughness: 0.35
							})
						);
						token.position.set(
							Math.cos(satellite.angle) * 2.05,
							Math.sin(satellite.angle) * 0.72,
							Math.sin(satellite.angle) * 0.45
						);
						orbit.add(token);
					}

					scene.add(new THREE.HemisphereLight(0xffffff, 0x182e5f, 2.1));
					const keyLight = new THREE.DirectionalLight(0xffedcc, 3.2);
					keyLight.position.set(-3, 4, 5);
					scene.add(keyLight);

					const resize = () => {
						if (!renderer || !camera || !canvas.parentElement) return;
						const { width, height } = canvas.parentElement.getBoundingClientRect();
						if (width === 0 || height === 0) return;
						renderer.setSize(width, height, false);
						camera.aspect = width / height;
						camera.updateProjectionMatrix();
						render();
					};

					resizeObserver = new ResizeObserver(resize);
					resizeObserver.observe(canvas.parentElement!);
					intersectionObserver = new IntersectionObserver(([entry]) => {
						isVisible = entry.isIntersecting;
						cancelAnimationFrame(animationFrame);
						if (isVisible) render();
					});
					intersectionObserver.observe(canvas);
					reduceMotion.addEventListener('change', handleMotionChange);
					resize();
				} catch (error) {
					console.warn(
						'The decorative 3D scene is unavailable; showing its static fallback.',
						error
					);
					failed = true;
				}
			})
			.catch((error: unknown) => {
				console.error('The decorative 3D scene could not be loaded.', error);
				failed = true;
			});

		return () => {
			disposed = true;
			cancelAnimationFrame(animationFrame);
			resizeObserver?.disconnect();
			intersectionObserver?.disconnect();
			reduceMotion.removeEventListener('change', handleMotionChange);
			scene?.traverse((object) => {
				if (object.type !== 'Mesh') return;
				const mesh = object as import('three').Mesh;
				mesh.geometry.dispose();
				if (Array.isArray(mesh.material)) mesh.material.forEach((material) => material.dispose());
				else mesh.material.dispose();
			});
			renderer?.dispose();
		};
	});

	function toggleMotion() {
		paused = !paused;
	}
</script>

<div class="orb-scene" class:failed class:paused>
	<div class="orb-fallback" aria-hidden="true"></div>
	<canvas bind:this={canvas} aria-hidden="true"></canvas>
	<button class="motion-toggle" type="button" aria-pressed={paused} onclick={toggleMotion}>
		{paused ? 'Resume motion' : 'Pause motion'}
	</button>
	<p class="orb-caption">Curiosity looks good on you.</p>
</div>

<style>
	.orb-scene {
		position: relative;
		width: min(100%, 31rem);
		aspect-ratio: 1;
		margin: 0 auto;
	}

	canvas {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}

	.orb-fallback {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 38%;
		aspect-ratio: 1;
		border: 1px solid rgb(212 175 106 / 65%);
		border-radius: 36% 64% 62% 38% / 43% 40% 60% 57%;
		background: radial-gradient(circle at 30% 26%, #f3dfb7, #c8a061 34%, #6d4c2d 72%, #182e5f);
		box-shadow:
			0 0 5rem rgb(200 160 97 / 35%),
			inset -1rem -1rem 2rem rgb(24 46 95 / 42%);
		transform: translate(-50%, -50%) rotate(-16deg);
		animation: breathe 7s ease-in-out infinite alternate;
	}

	.orb-scene::before,
	.orb-scene::after {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 73%;
		aspect-ratio: 1;
		border: 1px solid rgb(212 175 106 / 36%);
		border-radius: 50%;
		content: '';
		transform: translate(-50%, -50%) rotate(-26deg) scaleY(0.4);
	}

	.orb-scene::after {
		transform: translate(-50%, -50%) rotate(62deg) scaleY(0.44);
	}

	.orb-scene.paused .orb-fallback {
		animation-play-state: paused;
	}

	.motion-toggle {
		position: absolute;
		z-index: 2;
		top: 0.45rem;
		right: 1rem;
		padding: 0.4rem 0.6rem;
		border: 1px solid rgb(255 255 255 / 24%);
		border-radius: 99px;
		background: rgb(18 31 59 / 68%);
		color: rgb(255 255 255 / 82%);
		font-size: 0.68rem;
		cursor: pointer;
	}

	.motion-toggle:hover {
		background: rgb(18 31 59 / 92%);
	}

	.orb-caption {
		position: absolute;
		right: 0;
		bottom: 1rem;
		left: 0;
		color: rgb(253 249 242 / 72%);
		font-size: 0.82rem;
		letter-spacing: 0.1em;
		text-align: center;
		text-transform: uppercase;
	}

	@keyframes breathe {
		from {
			border-radius: 36% 64% 62% 38% / 43% 40% 60% 57%;
		}
		to {
			border-radius: 57% 43% 40% 60% / 55% 62% 38% 45%;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.orb-fallback {
			animation: none;
		}

		.motion-toggle {
			display: none;
		}
	}
</style>
