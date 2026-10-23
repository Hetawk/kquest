<script lang="ts">
	import { onMount } from 'svelte';

	let canvas: HTMLCanvasElement;
	let failed = $state(false);

	onMount(() => {
		let disposed = false;
		let frame = 0;
		let renderer: import('three').WebGLRenderer | undefined;
		let scene: import('three').Scene | undefined;
		let camera: import('three').PerspectiveCamera | undefined;
		let figures: import('three').Group[] = [];
		let confetti: import('three').Mesh[] = [];
		const figureHeights = [1, 0.68, 0.46];
		let resizeObserver: ResizeObserver | undefined;
		let intersectionObserver: IntersectionObserver | undefined;
		let handleMotionChange: (() => void) | undefined;
		const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
		let visible = true;
		let hasEntered = false;
		let startedAt = performance.now();

		const render = () => {
			if (!renderer || !scene || !camera || disposed) return;
			const elapsed = (performance.now() - startedAt) / 1000;
			if (!reduceMotion.matches && visible) {
				figures.forEach((figure, index) => {
					const delay = index * 0.22;
					const progress = Math.min(1, Math.max(0, (elapsed - delay) / 0.7));
					const eased = 1 - (1 - progress) ** 3;
					figure.position.y = figureHeights[index] - 0.35 * (1 - eased);
					figure.scale.setScalar(eased);
					figure.rotation.y = Math.sin(elapsed * 0.55 + index) * 0.08;
				});
				confetti.forEach((piece, index) => {
					const delay = (index % 8) * 0.12;
					const fall = elapsed - delay;
					piece.visible = fall >= 0 && fall < 2.5;
					if (piece.visible) {
						piece.position.y = 3.3 - fall * 1.35;
						piece.rotation.x += 0.025;
						piece.rotation.y += 0.035;
					}
				});
				frame = requestAnimationFrame(render);
			} else {
				figures.forEach((figure, index) => {
					figure.position.y = figureHeights[index];
					figure.scale.setScalar(1);
					figure.rotation.y = 0;
				});
				confetti.forEach((piece) => (piece.visible = false));
			}
			renderer.render(scene, camera);
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
					camera.position.set(0, 2.15, 9.2);
					camera.lookAt(0, 0.8, 0);

					scene.add(new THREE.HemisphereLight(0xfff8eb, 0x182e5f, 2.4));
					const keyLight = new THREE.DirectionalLight(0xffedcc, 3);
					keyLight.position.set(-3, 5, 6);
					scene.add(keyLight);
					const rimLight = new THREE.PointLight(0x9eafd9, 8, 14);
					rimLight.position.set(4, 3, 1);
					scene.add(rimLight);

					const colors = [
						{ metal: 0xc8a061, cloth: 0x9b7132, x: 0 },
						{ metal: 0xc8d0d8, cloth: 0x748091, x: -1.55 },
						{ metal: 0xb9784a, cloth: 0x8e4f2f, x: 1.55 }
					];
					const platformGeometry = new THREE.BoxGeometry(1.35, 1, 1.1);
					const topGeometry = new THREE.BoxGeometry(1.43, 0.12, 1.18);
					const headGeometry = new THREE.SphereGeometry(0.22, 20, 16);
					const bodyGeometry = new THREE.CapsuleGeometry(0.2, 0.46, 4, 10);
					const armGeometry = new THREE.CapsuleGeometry(0.065, 0.28, 4, 8);
					const trimGeometry = new THREE.TorusGeometry(0.28, 0.035, 8, 24);

					for (const [index, item] of colors.entries()) {
						const podium = new THREE.Group();
						podium.position.set(item.x, -0.15, 0);
						const height = index === 0 ? 1.02 : index === 1 ? 0.7 : 0.48;
						const base = new THREE.Mesh(
							platformGeometry,
							new THREE.MeshStandardMaterial({
								color: item.metal,
								metalness: 0.7,
								roughness: 0.29
							})
						);
						base.scale.y = height;
						base.position.y = height / 2;
						podium.add(base);
						const top = new THREE.Mesh(
							topGeometry,
							new THREE.MeshStandardMaterial({
								color: item.metal,
								metalness: 0.78,
								roughness: 0.22
							})
						);
						top.position.y = height + 0.05;
						podium.add(top);
						scene.add(podium);

						const figure = new THREE.Group();
						figure.position.set(item.x, figureHeights[index], 0.48);
						const body = new THREE.Mesh(
							bodyGeometry,
							new THREE.MeshStandardMaterial({
								color: item.cloth,
								roughness: 0.62,
								metalness: 0.08
							})
						);
						body.position.y = 0.35;
						figure.add(body);
						for (const side of [-1, 1]) {
							const arm = new THREE.Mesh(
								armGeometry,
								new THREE.MeshStandardMaterial({ color: item.cloth, roughness: 0.62 })
							);
							arm.position.set(side * 0.25, 0.44, 0.03);
							arm.rotation.z = side * -0.18;
							figure.add(arm);
						}
						const head = new THREE.Mesh(
							headGeometry,
							new THREE.MeshStandardMaterial({ color: 0xf2c8a5, roughness: 0.72 })
						);
						head.position.y = 0.83;
						figure.add(head);
						const hair = new THREE.Mesh(
							new THREE.SphereGeometry(0.225, 20, 10, 0, Math.PI * 2, 0, Math.PI * 0.52),
							new THREE.MeshStandardMaterial({ color: 0x30271f, roughness: 0.86 })
						);
						hair.position.y = 0.87;
						figure.add(hair);
						const halo = new THREE.Mesh(
							trimGeometry,
							new THREE.MeshBasicMaterial({
								color: item.metal,
								transparent: true,
								opacity: 0.72
							})
						);
						halo.position.y = 1.27;
						halo.rotation.x = Math.PI / 2;
						figure.add(halo);
						scene.add(figure);
						figures.push(figure);
					}

					const confettiGeometry = new THREE.OctahedronGeometry(0.055, 0);
					const confettiMaterials = [0xe5bd6e, 0x8c9fdb, 0xd98a68, 0x77a98b].map(
						(color) =>
							new THREE.MeshStandardMaterial({
								color,
								roughness: 0.52,
								metalness: 0.18
							})
					);
					for (let index = 0; index < 24; index += 1) {
						const piece = new THREE.Mesh(
							confettiGeometry,
							confettiMaterials[index % confettiMaterials.length]
						);
						piece.position.set((Math.random() - 0.5) * 6.2, 3.3, -0.4 + Math.random() * 0.7);
						piece.rotation.set(Math.random() * Math.PI, Math.random() * Math.PI, 0);
						piece.visible = false;
						scene.add(piece);
						confetti.push(piece);
					}

					const resize = () => {
						if (!renderer || !camera || !canvas.parentElement) return;
						const { width, height } = canvas.parentElement.getBoundingClientRect();
						if (!width || !height) return;
						renderer.setSize(width, height, false);
						camera.aspect = width / height;
						camera.updateProjectionMatrix();
						render();
					};
					resizeObserver = new ResizeObserver(resize);
					resizeObserver.observe(canvas.parentElement!);
					intersectionObserver = new IntersectionObserver(([entry]) => {
						visible = entry.isIntersecting;
						cancelAnimationFrame(frame);
						if (visible) {
							if (!hasEntered) {
								hasEntered = true;
								startedAt = performance.now();
							}
							render();
						}
					});
					intersectionObserver.observe(canvas);
					handleMotionChange = () => {
						cancelAnimationFrame(frame);
						render();
					};
					reduceMotion.addEventListener('change', handleMotionChange);
					resize();
				} catch (error) {
					console.warn('The 3D results scene is unavailable; showing the text podium.', error);
					failed = true;
				}
			})
			.catch((error: unknown) => {
				console.error('The 3D results scene could not be loaded.', error);
				failed = true;
			});

		return () => {
			disposed = true;
			cancelAnimationFrame(frame);
			resizeObserver?.disconnect();
			intersectionObserver?.disconnect();
			if (handleMotionChange) reduceMotion.removeEventListener('change', handleMotionChange);
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
</script>

<div class="podium-scene" class:failed aria-hidden="true">
	<canvas bind:this={canvas}></canvas>
	<div class="scene-fallback"></div>
</div>

<style>
	.podium-scene {
		position: relative;
		width: 100%;
		height: clamp(10rem, 32vw, 17rem);
		overflow: hidden;
		margin: 0.7rem auto 0;
		border-radius: 1rem;
		background:
			radial-gradient(ellipse at 50% 78%, rgb(226 204 164 / 36%), transparent 54%),
			linear-gradient(180deg, #fffdf9, #f8f4eb);
	}

	canvas {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}

	.scene-fallback {
		position: absolute;
		inset: 18% 15% 10%;
		background:
			radial-gradient(ellipse at 50% 85%, #c8a061 0 16%, transparent 17%),
			radial-gradient(ellipse at 26% 96%, #c8d0d8 0 13%, transparent 14%),
			radial-gradient(ellipse at 74% 98%, #b9784a 0 12%, transparent 13%);
		opacity: 0;
	}

	.failed .scene-fallback {
		opacity: 0.2;
	}

	@media (prefers-reduced-motion: reduce) {
		.podium-scene {
			background-color: #faf7f0;
		}
	}
</style>
