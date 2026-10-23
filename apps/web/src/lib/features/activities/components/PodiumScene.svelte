<script lang="ts">
	import { onMount } from 'svelte';

	type CharacterLook = {
		body: number;
		face: number;
		belly: number;
		accent: number;
		detail: number;
		ears: 'point' | 'round' | 'long' | 'none';
		species: string;
	};

	const characterLooks: Record<string, CharacterLook> = {
		fox: {
			body: 0xd97836,
			face: 0xfff1de,
			belly: 0xf4dfc0,
			accent: 0x8e3c2b,
			detail: 0xfff1de,
			ears: 'point',
			species: 'fox'
		},
		panda: {
			body: 0xf4f5f4,
			face: 0xffffff,
			belly: 0xffffff,
			accent: 0x252a32,
			detail: 0xd5908b,
			ears: 'round',
			species: 'panda'
		},
		lion: {
			body: 0xd89b42,
			face: 0xffe1a7,
			belly: 0xf4d18a,
			accent: 0xa9502c,
			detail: 0x7c4227,
			ears: 'round',
			species: 'lion'
		},
		frog: {
			body: 0x63ad69,
			face: 0x88ca78,
			belly: 0xd7edab,
			accent: 0x327a51,
			detail: 0x234a3a,
			ears: 'none',
			species: 'frog'
		},
		cat: {
			body: 0x9097a8,
			face: 0xf5e9dc,
			belly: 0xf5e9dc,
			accent: 0xc57f83,
			detail: 0x4c5261,
			ears: 'point',
			species: 'cat'
		},
		penguin: {
			body: 0x364d6c,
			face: 0xf8f7ed,
			belly: 0xf8f7ed,
			accent: 0xe89a47,
			detail: 0x243248,
			ears: 'none',
			species: 'penguin'
		},
		tiger: {
			body: 0xe77c37,
			face: 0xffefd7,
			belly: 0xffe6c9,
			accent: 0x302b2b,
			detail: 0x9b482d,
			ears: 'round',
			species: 'tiger'
		},
		rabbit: {
			body: 0xf2e9e2,
			face: 0xfff9f4,
			belly: 0xfff9f4,
			accent: 0xd68da0,
			detail: 0x655b61,
			ears: 'long',
			species: 'rabbit'
		},
		owl: {
			body: 0x8b654d,
			face: 0xf4dfb4,
			belly: 0xf4dfb4,
			accent: 0xb98d61,
			detail: 0x483a35,
			ears: 'point',
			species: 'owl'
		},
		unicorn: {
			body: 0xf0e4f1,
			face: 0xfff7fb,
			belly: 0xf7e6f3,
			accent: 0xb880ca,
			detail: 0x765486,
			ears: 'point',
			species: 'unicorn'
		},
		koala: {
			body: 0x929aa5,
			face: 0xd8dce0,
			belly: 0xe8e9e8,
			accent: 0xb9818a,
			detail: 0x454b57,
			ears: 'round',
			species: 'koala'
		},
		dragon: {
			body: 0x4c9a87,
			face: 0x91c9a4,
			belly: 0xd2e7b5,
			accent: 0xd98d55,
			detail: 0x315d5a,
			ears: 'point',
			species: 'dragon'
		}
	};

	let {
		characterIds,
		onReady = () => {},
		onFailure = () => {}
	}: {
		characterIds: Array<string | null>;
		onReady?: () => void;
		onFailure?: () => void;
	} = $props();

	let canvas: HTMLCanvasElement;

	onMount(() => {
		let disposed = false;
		let frame = 0;
		let renderer: import('three').WebGLRenderer | undefined;
		let scene: import('three').Scene | undefined;
		let camera: import('three').OrthographicCamera | undefined;
		let resizeObserver: ResizeObserver | undefined;
		let intersectionObserver: IntersectionObserver | undefined;
		let handleMotionChange: (() => void) | undefined;
		const figures: Array<{
			group: import('three').Group;
			head: import('three').Group;
			waveArm: import('three').Group;
			tail: import('three').Group | null;
			baseX: number;
			baseY: number;
			scale: number;
			index: number;
		}> = [];
		const podiumSelectors = [
			'.winner.place-second .podium-block',
			'.winner.place-first .podium-block',
			'.winner.place-third .podium-block'
		];
		const mascotScale = 0.9;
		const pixelsPerWorldUnit = 64;
		const confetti: import('three').Mesh[] = [];
		const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
		let visible = true;
		let hasEntered = false;
		let startedAt = performance.now();

		const render = () => {
			if (!renderer || !scene || !camera || disposed) return;
			const elapsed = (performance.now() - startedAt) / 1000;
			if (!reduceMotion.matches && visible) {
				figures.forEach(({ group, head, waveArm, tail, baseX, baseY, scale, index }) => {
					const delay = [0.22, 0, 0.4][index] ?? index * 0.2;
					const progress = Math.min(1, Math.max(0, (elapsed - delay) / 0.72));
					const eased = 1 - (1 - progress) ** 3;
					group.position.x = baseX;
					group.position.y = baseY - 0.32 * (1 - eased) + Math.sin(elapsed * 2 + index) * 0.025;
					group.scale.setScalar(scale * eased);
					group.rotation.y = Math.sin(elapsed * 0.62 + index) * 0.22;
					head.rotation.y = Math.sin(elapsed * 0.8 + index * 1.4) * 0.15;
					waveArm.rotation.z = -0.85 + Math.sin(elapsed * 2.4 + index) * 0.13;
					if (tail) tail.rotation.y = Math.sin(elapsed * 2.1 + index) * 0.28;
				});
				confetti.forEach((piece, index) => {
					const delay = (index % 8) * 0.1;
					const fall = elapsed - delay;
					piece.visible = fall >= 0 && fall < 2.2;
					if (piece.visible) {
						piece.position.y = 2.2 - fall * 1.25;
						piece.rotation.x += 0.025;
						piece.rotation.y += 0.035;
					}
				});
				frame = requestAnimationFrame(render);
			} else {
				figures.forEach(({ group, head, waveArm, tail, baseX, baseY, scale }) => {
					group.position.x = baseX;
					group.position.y = baseY;
					group.scale.setScalar(scale);
					group.rotation.y = 0;
					head.rotation.y = 0;
					waveArm.rotation.z = -0.85;
					if (tail) tail.rotation.y = 0;
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
					camera = new THREE.OrthographicCamera(-2, 2, 2.4, -2.4, 0.1, 50);
					camera.position.set(0, 0, 10);
					camera.lookAt(0, 0, 0);

					scene.add(new THREE.HemisphereLight(0xfff8eb, 0x182e5f, 2.2));
					const keyLight = new THREE.DirectionalLight(0xffedcc, 3);
					keyLight.position.set(-3, 5, 6);
					scene.add(keyLight);
					const rimLight = new THREE.PointLight(0x9eafd9, 5, 14);
					rimLight.position.set(4, 3, 1);
					scene.add(rimLight);

					const materials: Record<number, import('three').MeshStandardMaterial> = {};
					const material = (color: number) => {
						let current = materials[color];
						if (!current) {
							current = materials[color] = new THREE.MeshStandardMaterial({
								color,
								roughness: 0.62,
								metalness: 0.02
							});
						}
						return current;
					};
					const sphere = new THREE.SphereGeometry(1, 24, 18);
					const cone = new THREE.ConeGeometry(1, 1, 10);
					const capsule = new THREE.CapsuleGeometry(0.1, 0.28, 4, 10);

					const addSphere = (
						parent: import('three').Group,
						color: number,
						position: [number, number, number],
						scale: [number, number, number]
					) => {
						const mesh = new THREE.Mesh(sphere, material(color));
						mesh.position.set(...position);
						mesh.scale.set(...scale);
						parent.add(mesh);
						return mesh;
					};
					const addCone = (
						parent: import('three').Group,
						color: number,
						position: [number, number, number],
						scale: [number, number, number],
						rotationZ = 0
					) => {
						const mesh = new THREE.Mesh(cone, material(color));
						mesh.position.set(...position);
						mesh.scale.set(...scale);
						mesh.rotation.z = rotationZ;
						parent.add(mesh);
					};
					const addCapsule = (
						parent: import('three').Group,
						color: number,
						position: [number, number, number],
						scale: [number, number, number],
						rotationZ = 0
					) => {
						const mesh = new THREE.Mesh(capsule, material(color));
						mesh.position.set(...position);
						mesh.scale.set(...scale);
						mesh.rotation.z = rotationZ;
						parent.add(mesh);
					};

					const createMascot = (characterId: string, index: number) => {
						const look = characterLooks[characterId] ?? characterLooks.fox;
						const group = new THREE.Group();
						const baseY = 0;
						const scale = mascotScale;
						group.scale.setScalar(mascotScale);
						scene!.add(group);

						const torso = new THREE.Group();
						group.add(torso);
						addSphere(torso, look.body, [0, 0.4, 0], [0.3, 0.37, 0.25]);
						addSphere(torso, look.belly, [0, 0.39, 0.222], [0.2, 0.25, 0.055]);

						for (const side of [-1, 1]) {
							addSphere(torso, look.body, [side * 0.16, 0.1, 0.035], [0.13, 0.16, 0.16]);
						}

						const leftArm = new THREE.Group();
						leftArm.position.set(-0.28, 0.56, 0.02);
						torso.add(leftArm);
						addCapsule(leftArm, look.body, [-0.015, -0.12, 0], [1, 1, 1], -0.42);

						const waveArm = new THREE.Group();
						waveArm.position.set(0.28, 0.56, 0.02);
						torso.add(waveArm);
						addCapsule(waveArm, look.body, [0, -0.12, 0], [1, 1, 1]);
						addSphere(waveArm, look.face, [0, -0.27, 0], [0.105, 0.09, 0.09]);

						const head = new THREE.Group();
						head.position.y = 0.88;
						group.add(head);

						if (look.species === 'lion') {
							addSphere(head, look.accent, [0, 0, -0.035], [0.48, 0.47, 0.35]);
						}
						addSphere(
							head,
							look.face,
							[0, 0, 0.025],
							look.species === 'penguin'
								? [0.36, 0.38, 0.32]
								: look.species === 'frog'
									? [0.4, 0.33, 0.31]
									: [0.38, 0.36, 0.32]
						);

						if (look.ears === 'point') {
							for (const side of [-1, 1]) {
								addCone(head, look.body, [side * 0.245, 0.29, 0], [0.14, 0.3, 0.12], side * -0.18);
								if (look.species === 'fox' || look.species === 'cat') {
									addSphere(head, look.accent, [side * 0.245, 0.26, 0.105], [0.07, 0.15, 0.035]);
								}
							}
						} else if (look.ears === 'round') {
							for (const side of [-1, 1]) {
								const koala = look.species === 'koala';
								addSphere(
									head,
									look.body,
									[side * (koala ? 0.38 : 0.27), koala ? 0.05 : 0.25, -0.015],
									[koala ? 0.19 : 0.14, koala ? 0.2 : 0.14, 0.1]
								);
								addSphere(
									head,
									look.accent,
									[side * (koala ? 0.38 : 0.27), koala ? 0.05 : 0.25, 0.066],
									[koala ? 0.11 : 0.075, koala ? 0.12 : 0.075, 0.035]
								);
							}
						} else if (look.ears === 'long') {
							for (const side of [-1, 1]) {
								addCapsule(head, look.body, [side * 0.17, 0.39, 0], [0.85, 1.1, 0.8], side * -0.12);
								addSphere(head, look.accent, [side * 0.17, 0.4, 0.08], [0.065, 0.2, 0.025]);
							}
						}

						const eyeY = look.species === 'frog' ? 0.18 : 0.035;
						if (look.species === 'panda' || look.species === 'tiger') {
							for (const side of [-1, 1]) {
								addSphere(head, look.accent, [side * 0.15, eyeY, 0.29], [0.115, 0.14, 0.045]);
							}
						}
						if (look.species === 'owl') {
							for (const side of [-1, 1]) {
								addSphere(head, look.accent, [side * 0.15, eyeY, 0.29], [0.14, 0.15, 0.06]);
							}
						}
						for (const side of [-1, 1]) {
							const eyeX = side * (look.species === 'frog' ? 0.2 : 0.145);
							const eyeZ = look.species === 'frog' ? 0.25 : 0.32;
							addSphere(head, 0xffffff, [eyeX, eyeY, eyeZ], [0.066, 0.082, 0.05]);
							addSphere(head, 0x272c36, [eyeX, eyeY - 0.004, eyeZ + 0.044], [0.034, 0.049, 0.025]);
						}

						if (look.species === 'frog') {
							addSphere(head, look.face, [-0.2, 0.27, 0.12], [0.14, 0.16, 0.13]);
							addSphere(head, look.face, [0.2, 0.27, 0.12], [0.14, 0.16, 0.13]);
						} else if (look.species === 'penguin') {
							addCone(head, look.accent, [0, -0.12, 0.36], [0.11, 0.18, 0.11], Math.PI / 2);
							addSphere(head, look.accent, [0, -0.28, 0.27], [0.13, 0.05, 0.1]);
						} else if (look.species === 'unicorn') {
							addCone(head, 0xe8bf72, [0, 0.39, 0.01], [0.09, 0.35, 0.09]);
							addSphere(head, look.accent, [-0.25, 0.04, 0.22], [0.09, 0.24, 0.08]);
						} else if (look.species === 'dragon') {
							for (const side of [-1, 1]) {
								addCone(
									head,
									look.accent,
									[side * 0.25, 0.31, -0.02],
									[0.1, 0.24, 0.09],
									side * -0.25
								);
							}
						} else {
							addSphere(head, look.face, [0, -0.14, 0.31], [0.2, 0.12, 0.11]);
							addSphere(head, look.detail, [0, -0.085, 0.405], [0.045, 0.035, 0.035]);
							addSphere(head, look.face, [0, -0.24, 0.34], [0.085, 0.035, 0.04]);
						}

						if (look.species === 'fox' || look.species === 'tiger') {
							for (const side of [-1, 1]) {
								addSphere(
									head,
									look.species === 'fox' ? look.face : look.accent,
									[side * 0.28, -0.13, 0.12],
									[0.11, 0.06, 0.035]
								);
							}
						}

						if (look.species === 'tiger') {
							for (const side of [-1, 1]) {
								addSphere(head, look.accent, [side * 0.28, 0.04, 0.2], [0.055, 0.022, 0.025]);
							}
							addSphere(head, look.accent, [0, 0.26, 0.28], [0.028, 0.09, 0.025]);
						}

						if (look.species === 'owl') {
							addCone(head, look.accent, [0, -0.13, 0.37], [0.09, 0.14, 0.08], Math.PI / 2);
						}

						let tail: import('three').Group | null = null;
						if (look.species === 'fox' || look.species === 'cat' || look.species === 'dragon') {
							tail = new THREE.Group();
							tail.position.set(0.18, 0.25, -0.17);
							group.add(tail);
							addSphere(tail, look.body, [0.12, 0.01, 0], [0.19, 0.2, 0.28]);
							addSphere(
								tail,
								look.species === 'fox' ? look.face : look.accent,
								[0.22, 0.015, -0.2],
								[0.11, 0.12, 0.1]
							);
						}

						if (look.species === 'penguin' || look.species === 'owl' || look.species === 'dragon') {
							for (const side of [-1, 1]) {
								const wingColor = look.species === 'penguin' ? look.detail : look.body;
								const wing = addSphere(
									group,
									wingColor,
									[side * 0.31, 0.42, -0.12],
									[0.12, look.species === 'dragon' ? 0.33 : 0.25, 0.09]
								);
								wing.rotation.z = side * -0.32;
							}
						}

						if (look.species === 'dragon') {
							for (const side of [-1, 1]) {
								addSphere(group, look.accent, [side * 0.17, 0.09, 0.23], [0.09, 0.12, 0.04]);
							}
						}

						return { group, head, waveArm, tail, baseX: 0, baseY, scale, index };
					};

					for (const [index, characterId] of characterIds.entries()) {
						if (characterId) figures.push(createMascot(characterId, index));
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
					for (let index = 0; index < 20; index += 1) {
						const piece = new THREE.Mesh(
							confettiGeometry,
							confettiMaterials[index % confettiMaterials.length]
						);
						piece.position.set((Math.random() - 0.5) * 5.5, 2.2, -0.4 + Math.random() * 0.7);
						piece.rotation.set(Math.random() * Math.PI, Math.random() * Math.PI, 0);
						piece.visible = false;
						scene.add(piece);
						confetti.push(piece);
					}

					const resize = () => {
						if (!renderer || !camera || !canvas.parentElement) return;
						const sceneElement = canvas.parentElement;
						const { width, height } = sceneElement.getBoundingClientRect();
						if (!width || !height) return;
						const halfViewHeight = height / pixelsPerWorldUnit / 2;
						const halfViewWidth = width / pixelsPerWorldUnit / 2;
						camera.top = halfViewHeight;
						camera.bottom = -halfViewHeight;
						camera.left = -halfViewWidth;
						camera.right = halfViewWidth;
						camera.updateProjectionMatrix();
						const sceneRect = sceneElement.getBoundingClientRect();
						const podiumContainer = sceneElement.parentElement;
						figures.forEach((figure) => {
							const { group, index } = figure;
							const selector = podiumSelectors[index];
							const podiumFace = selector ? podiumContainer?.querySelector(selector) : null;
							if (!(podiumFace instanceof HTMLElement)) return;
							const faceRect = podiumFace.getBoundingClientRect();
							const centerX = faceRect.left + faceRect.width / 2 - sceneRect.left;
							const faceTop = faceRect.top - sceneRect.top;
							figure.baseX = (centerX - width / 2) / pixelsPerWorldUnit;
							figure.baseY = halfViewHeight - faceTop / pixelsPerWorldUnit;
							group.position.set(figure.baseX, figure.baseY, 0);
						});
						renderer.setSize(width, height, false);
						cancelAnimationFrame(frame);
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
						} else {
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
					onReady();
				} catch (error) {
					console.warn('The animated results characters are unavailable.', error);
					onFailure();
				}
			})
			.catch((error: unknown) => {
				console.error('The animated results characters could not be loaded.', error);
				onFailure();
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
				if (Array.isArray(mesh.material)) mesh.material.forEach((item) => item.dispose());
				else mesh.material.dispose();
			});
			renderer?.dispose();
		};
	});
</script>

<div class="podium-scene" aria-hidden="true">
	<canvas bind:this={canvas}></canvas>
</div>

<style>
	.podium-scene {
		position: absolute;
		z-index: 0;
		inset: -3rem 0 0;
		pointer-events: none;
	}

	canvas {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}
</style>
