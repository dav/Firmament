/* =============================================================================
   The landing page's scroll narrative.

   This is a port of the app's first-launch intro tour (App/Intro/IntroScript.swift)
   from a narrated timeline to a scrolled one. The nine beats, their captions,
   their camera keyframes and their scene actions are the same; the only
   difference is what advances them. In the app a beat lasts as long as its
   narration; here it lasts as long as its section's slice of scroll, declared
   as data-span (in vh) on each <section class="beat"> in index.html.

   Two stylized worlds, exactly as in the app:

     track   beats 1-4   a circular track at night, seen from a race car
     space   beats 5-9   the Sun at the origin, Earth on a 60-unit orbit,
                         a lattice laid over the orbital plane

   They share a world origin but are never visible at the same time. The seam
   between them is a match cut: beat 4 pushes the camera into the globe on the
   car's hood until it fills the frame, and beat 5 opens on the real Earth at
   the same apparent size. Both framings work out to a 42.5-degree angular
   radius, which is what makes the cut invisible.

   Anything moving on its own — the car's lap, Earth's orbit and spin — runs on
   wall-clock time, not on scroll. Stop scrolling and the reference points keep
   streaming past you, which is the entire point being made.
   ============================================================================= */

import * as THREE from "three";

const { gsap, ScrollTrigger, Lenis } = window;
gsap.registerPlugin(ScrollTrigger);

const reduceMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
).matches;

/* -----------------------------------------------------------------------------
   Scene-scale tuning. Ported from TourTuning: track space is roughly
   1 unit = 1 m, and heliocentric space compresses wildly on purpose (Earth
   radius 1, orbit radius 60) so that the story reads.
   -------------------------------------------------------------------------- */
const T = {
    // Track
    trackRadius: 40,
    trackHalfWidth: 5,
    grassRadius: 220,
    postCount: 48,
    postHeight: 1.6,
    postOffsetFromEdge: 1.8,
    carLapDuration: 34, // seconds per lap: one post every ~0.7 s in POV

    // Heliocentric
    orbitRadius: 60,
    // Larger than the app's 1.0. On a phone held at arm's length a one-unit
    // Earth reads fine; on a laptop, forty-odd units away in the wide framing,
    // it collapses to a dot. Every camera distance that depends on it is
    // written as a multiple of R below, so this stays a single knob.
    earthRadius: 2,
    sunRadius: 4,
    earthOrbitPeriod: 150,
    gridSpacing: 5,
    gridExtent: 70,
    orbitSegmentCount: 256,
    nodeCubeEdgeFraction: 0.18,
    earthTextureLongitudeOffsetDegrees: -152,
    earthAxialTiltDegrees: 23.5,
    earthSpinSecondsPerRevolution: 4,

    // Hood ornament globe — also the morph target at the track/space seam.
    ornamentGlobeCenter: new THREE.Vector3(0, 1.22, -1.5),
    ornamentGlobeRadius: 0.095,
};

/* -----------------------------------------------------------------------------
   Small math helpers
   -------------------------------------------------------------------------- */
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerp = (a, b, t) => a + (b - a) * t;

/** Hermite ease used for every keyframe segment and every fade. */
function smoothstep(edge0, edge1, x) {
    const t = clamp01((x - edge0) / (edge1 - edge0));
    return t * t * (3 - 2 * t);
}

/** Progress of `x` through [a, b], clamped. */
const spanProgress = (x, a, b) => clamp01((x - a) / (b - a));

const V = (x, y, z) => new THREE.Vector3(x, y, z);

/* -----------------------------------------------------------------------------
   Camera frames

   A frame is a moving pose in the world: an origin plus an orientation whose
   -z axis points "forward" and whose +y is up, matching the camera convention.
   Keyframes are written in frame-local coordinates, so the same numbers keep
   working while the car laps the track and the Earth runs its orbit.
   -------------------------------------------------------------------------- */
const UP = V(0, 1, 0);

function frameMatrix(position, forward) {
    const z = forward.clone().negate().normalize();
    const x = new THREE.Vector3().crossVectors(UP, z).normalize();
    const y = new THREE.Vector3().crossVectors(z, x);
    return new THREE.Matrix4().makeBasis(x, y, z).setPosition(position);
}

/** Where the car is, and which way it is pointing, at scene time `t`. */
function carPose(t) {
    const a = (t / T.carLapDuration) * Math.PI * 2;
    const position = V(
        Math.sin(a) * T.trackRadius,
        0,
        Math.cos(a) * T.trackRadius,
    );
    const forward = V(Math.cos(a), 0, -Math.sin(a));
    return { position, forward, angle: a };
}

/** Where the Earth is at scene time `t`; forward points at the Sun. */
function earthPose(t) {
    const a = (t / T.earthOrbitPeriod) * Math.PI * 2;
    const position = V(
        Math.cos(a) * T.orbitRadius,
        0,
        Math.sin(a) * T.orbitRadius,
    );
    const forward = position.clone().negate().normalize();
    return { position, forward, angle: a };
}

function frameFor(name, t) {
    const pose = name === "car" ? carPose(t) : earthPose(t);
    return frameMatrix(pose.position, pose.forward);
}

/* -----------------------------------------------------------------------------
   The script — nine beats, the same nine the app narrates.

   `camera` keyframes carry a progress in [0,1] through the beat, a frame, a
   frame-local position and lookAt, and a vertical field of view. `actions`
   carry a target name, an effect, and the slice of beat progress they run over.
   -------------------------------------------------------------------------- */
const povPosition = V(0, 1.05, 0.2);
const povLookAt = V(0, 0.85, -10);
const povFov = 70;

/** Earth radius, spelled short because the beat-5 keyframes are all multiples. */
const R = T.earthRadius;

const pov = (progress) => ({
    progress,
    frame: "car",
    position: povPosition,
    lookAt: povLookAt,
    fov: povFov,
});

// The wide "watch the markers stream past" framing shared by the last two
// beats: high and pulled back, tracking the Earth so it stays put in frame
// while the world's grid nodes sail past it.
const holdPosition = V(0, 24, 34);
const holdLookAt = V(0, 0, -20);
const holdFov = 60;

const hold = (progress) => ({
    progress,
    frame: "earth",
    position: holdPosition,
    lookAt: holdLookAt,
    fov: holdFov,
});

const BEATS = [
    {
        id: "racecar",
        world: "track",
        camera: [
            // Wider and higher than the app's opening. The app can afford a
            // near chase shot because it is about to move; here frame zero is
            // the page's hero and has to hold still under a headline, so it
            // pulls back until the whole arc of the track is in it and tilts
            // the horizon down out of the type's way.
            { progress: 0, frame: "car", position: V(0, 21, 39), lookAt: V(0, 6, -19), fov: 50 },
            { progress: 0.45, frame: "car", position: V(0, 7, 11), lookAt: V(0, 0.6, -9), fov: 62 },
            pov(1),
        ],
        actions: [],
    },
    {
        id: "noSurroundings",
        world: "track",
        camera: [pov(0), pov(1)],
        actions: [
            { target: "grass", effect: "fade", from: 1, to: 0, range: [0.1, 0.5] },
            { target: "posts", effect: "fade", from: 1, to: 0, range: [0.5, 0.9] },
        ],
    },
    {
        id: "linesVanish",
        world: "track",
        camera: [pov(0), pov(1)],
        actions: [
            { target: "trackEdgeLines", effect: "fade", from: 1, to: 0, range: [0.2, 0.8] },
            { target: "trackPavement", effect: "fade", from: 1, to: 0, range: [0.6, 0.95] },
        ],
    },
    {
        id: "blackness",
        world: "track",
        camera: [
            pov(0),
            pov(0.55),
            // Notice the little globe on the hood…
            { progress: 0.75, frame: "car", position: V(0, 1.05, 0.1), lookAt: T.ornamentGlobeCenter, fov: 60 },
            // …and push into it until it fills the frame, ready to become the
            // real Earth in a match cut at the next beat's start.
            { progress: 1, frame: "car", position: V(0, 1.206, -1.36), lookAt: T.ornamentGlobeCenter, fov: 50 },
        ],
        actions: [
            { target: "car", effect: "fade", from: 1, to: 0, range: [0.6, 0.85] },
            // Bring the real Earth up to full opacity behind the full-frame
            // globe, so the cut lands on a solid Earth and not on black.
            { target: "earth", effect: "fade", from: 0, to: 1, range: [0.9, 1.0] },
        ],
    },
    {
        id: "earthReveal",
        world: "space",
        camera: [
            // Opens on the Earth at the apparent size the ornament globe filled
            // a frame ago (fov 50, ~43-degree radius — asin(R / 1.475R), which
            // is why the distance is written as a multiple and not a number),
            // then pulls back to reveal it whole, and the Sun with it.
            //
            // On the day side, not straight behind: in this frame -z points at
            // the Sun, so the lit hemisphere is the -z one and a camera on the
            // +z axis would open the reveal on midnight. Starting over the
            // sunlit shoulder puts the terminator across the disc.
            //
            // The middle keyframe is not a framing choice but a clearance one.
            // The camera has to get from the day side to (0, 3, 14) behind, and
            // interpolation between keyframes is a straight line: without a
            // waypoint swung out to the side, that line passes within a radius
            // of the Earth's centre and the camera flies through the planet.
            { progress: 0, frame: "earth", position: V(0.7188, 0.1897, -0.6689).multiplyScalar(1.475 * R), lookAt: V(0, 0, 0), fov: 50 },
            { progress: 0.4, frame: "earth", position: V(5.0, 1.8, 2.0).normalize().multiplyScalar(3.1 * R), lookAt: V(0, 0, 0), fov: 60 },
            { progress: 1, frame: "earth", position: V(0, 3, 14), lookAt: V(0, 0, -8), fov: 60 },
        ],
        actions: [
            { target: "ornamentGlobe", effect: "fade", from: 1, to: 0, range: [0.0, 0.08] },
            { target: "sun", effect: "fade", from: 0, to: 1, range: [0.2, 0.4] },
        ],
    },
    {
        id: "orbitDrawn",
        world: "space",
        camera: [
            { progress: 0, frame: "earth", position: V(0, 3, 14), lookAt: V(0, 0, -8), fov: 60 },
            { progress: 1, frame: "earth", position: V(0, 30, 45), lookAt: V(0, 0, -25), fov: 60 },
        ],
        actions: [{ target: "orbitPath", effect: "drawOrbit", range: [0.1, 0.9] }],
    },
    {
        id: "gridUnfolds",
        world: "space",
        // The camera stays locked to the Earth for the whole beat, so the grid
        // unfolds around an apparently stationary Earth. "Earth sails past the
        // grid" belongs to the next beat, once the markers are all in place.
        camera: [
            { progress: 0, frame: "earth", position: V(0, 30, 45), lookAt: V(0, 0, -25), fov: 60 },
            hold(1),
        ],
        actions: [{ target: "spaceGrid", effect: "unfoldGrid", range: [0.0, 0.8] }],
    },
    {
        id: "nodesAppear",
        world: "space",
        camera: [hold(0), hold(1)],
        actions: [{ target: "gridNodes", effect: "revealNodes", range: [0.0, 0.6] }],
    },
    {
        id: "zoomHome",
        world: "space",
        camera: [hold(0), hold(1)],
        actions: [{ target: "homeMarker", effect: "fade", from: 0, to: 1, range: [0.0, 0.15] }],
    },
];

/* Values every target sits at before any action has touched it. */
const INITIAL = {
    grass: 1,
    posts: 1,
    trackEdgeLines: 1,
    trackPavement: 1,
    car: 1,
    ornamentGlobe: 1,
    earth: 0,
    sun: 0,
    orbitPath: 0,
    spaceGrid: 0,
    gridNodes: 0,
    homeMarker: 0,
};

/* =============================================================================
   Scene construction
   ============================================================================= */

const canvas = document.getElementById("sky");
const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    alpha: true,
    powerPreference: "high-performance",
});
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setClearColor(0x000000, 0);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, 1, 0.02, 6000);

const trackRoot = new THREE.Group();
const spaceRoot = new THREE.Group();
scene.add(trackRoot, spaceRoot);

// Fog belongs to the track only — it is what makes the posts fall off into the
// dark. Space is switched to fogless so the far side of the lattice survives.
const trackFog = new THREE.Fog(0x05070c, 55, 190);

/** Targets are named handles the script's actions address. */
const targets = {};

/** A group of standard materials faded together.

    Fading means `transparent: true`, which moves a material into the sorted
    transparent pass — and a solid surface in that pass still has to write depth
    or the starfield shows straight through the car. Only genuinely additive
    things (the headlight pools, the Sun's glow) opt out. */
function fadeTarget(materials, { additive = false } = {}) {
    materials.forEach((m) => {
        m.transparent = true;
        if (additive) m.depthWrite = false;
    });
    return {
        set(v) {
            materials.forEach((m) => {
                m.opacity = v;
                m.visible = v > 0.002;
            });
        },
    };
}

/** A reveal-shader handle: `set` moves its threshold across the sweep. */
function revealTarget(material, maxKey, soft) {
    return {
        set(v) {
            material.uniforms.uThreshold.value = v * (maxKey + soft) - soft;
            material.uniforms.uOpacity.value = v > 0 ? 1 : 0;
        },
    };
}

/* -----------------------------------------------------------------------------
   The reveal shader.

   Every progressive reveal in the tour — the orbit drawing itself on, the grid
   unfolding sun-outward, the markers sweeping out from under the Earth — is the
   same operation: hide a vertex until some scalar key falls below a moving
   threshold. Doing it on the GPU means the reveal costs nothing per frame, and
   the sweep's origin can follow the Earth as a uniform.

   mode 0: key is radius in the orbital plane      (grid unfolds, sun outward)
   mode 1: key is distance from uCenter            (markers sweep outward)
   mode 2: key is angle travelled from uStartAngle (orbit draws on)
   -------------------------------------------------------------------------- */
function revealMaterial({ mode, color, soft, opacity = 1, additive = true }) {
    return new THREE.ShaderMaterial({
        uniforms: {
            uThreshold: { value: -1e9 },
            uSoft: { value: soft },
            uCenter: { value: new THREE.Vector3() },
            uStartAngle: { value: 0 },
            uColor: { value: new THREE.Color(color) },
            uOpacity: { value: 0 },
            uBase: { value: opacity },
            uMode: { value: mode },
        },
        vertexShader: `
            uniform float uThreshold, uSoft, uStartAngle;
            uniform vec3 uCenter;
            uniform int uMode;
            varying float vAlpha;
            const float TAU = 6.28318530718;
            void main() {
                float key;
                if (uMode == 0) {
                    key = length(position.xz);
                } else if (uMode == 1) {
                    key = distance(position, uCenter);
                } else {
                    float a = atan(position.z, position.x);
                    key = mod(a - uStartAngle, TAU);
                }
                vAlpha = 1.0 - smoothstep(uThreshold, uThreshold + uSoft, key);
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }
        `,
        fragmentShader: `
            uniform vec3 uColor;
            uniform float uOpacity, uBase;
            varying float vAlpha;
            void main() {
                float a = vAlpha * uOpacity * uBase;
                if (a < 0.004) discard;
                gl_FragColor = vec4(uColor, a);
            }
        `,
        transparent: true,
        depthWrite: false,
        blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
}

/* -----------------------------------------------------------------------------
   Stars. Shared by both worlds — the same sky is over the track and the orbit,
   which is quietly the thesis of the app.
   -------------------------------------------------------------------------- */
function buildStars() {
    const count = 2600;
    const pos = new Float32Array(count * 3);
    const col = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
        // Uniform on the sphere, so there is no clumping at the poles.
        const u = Math.random() * 2 - 1;
        const th = Math.random() * Math.PI * 2;
        const r = Math.sqrt(1 - u * u) * 1800;
        pos.set([r * Math.cos(th), u * 1800, r * Math.sin(th)], i * 3);

        // A few warm and a few cold ones keep the field from looking printed.
        const b = 0.35 + Math.pow(Math.random(), 2.2) * 0.65;
        const warm = Math.random() < 0.25;
        col.set(
            warm ? [b, b * 0.9, b * 0.78] : [b * 0.82, b * 0.9, b],
            i * 3,
        );
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    g.setAttribute("color", new THREE.BufferAttribute(col, 3));
    const stars = new THREE.Points(
        g,
        new THREE.PointsMaterial({
            size: 2.1,
            sizeAttenuation: false,
            vertexColors: true,
            transparent: true,
            opacity: 0.85,
            depthWrite: false,
            fog: false,
        }),
    );
    stars.frustumCulled = false;
    // Behind everything, always: drawn first, and writing no depth of its own,
    // so any surface that comes later simply paints over it.
    stars.renderOrder = -10;
    return stars;
}
scene.add(buildStars());

/* -----------------------------------------------------------------------------
   A radial-gradient sprite texture, used for the headlight pools and the Sun's
   glow. Generated rather than shipped, so the page carries one image total.
   -------------------------------------------------------------------------- */
function radialTexture(inner = "rgba(255,255,255,1)", outer = "rgba(255,255,255,0)") {
    const c = document.createElement("canvas");
    c.width = c.height = 256;
    const g = c.getContext("2d");
    const grad = g.createRadialGradient(128, 128, 0, 128, 128, 128);
    grad.addColorStop(0, inner);
    grad.addColorStop(0.45, inner.replace(/[\d.]+\)$/, "0.35)"));
    grad.addColorStop(1, outer);
    g.fillStyle = grad;
    g.fillRect(0, 0, 256, 256);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
}
const glowTexture = radialTexture();

const earthTexture = new THREE.TextureLoader().load("assets/earth-stylized.png?v=f46423f2");
earthTexture.colorSpace = THREE.SRGBColorSpace;
earthTexture.anisotropy = 4;

/* -----------------------------------------------------------------------------
   The track world
   -------------------------------------------------------------------------- */
function buildTrack() {
    const inner = T.trackRadius - T.trackHalfWidth;
    const outer = T.trackRadius + T.trackHalfWidth;

    // Grass. Barely lighter than the sky, but enough that its horizon reads —
    // which is what makes losing it in beat 2 land.
    const grass = new THREE.Mesh(
        new THREE.CircleGeometry(T.grassRadius, 96),
        new THREE.MeshBasicMaterial({ color: 0x0a1010 }),
    );
    grass.rotation.x = -Math.PI / 2;
    grass.position.y = -0.03;

    const pavement = new THREE.Mesh(
        new THREE.RingGeometry(inner, outer, 192, 1),
        new THREE.MeshBasicMaterial({ color: 0x1b1f27 }),
    );
    pavement.rotation.x = -Math.PI / 2;

    // Two headlight pools rather than one wash. They go with the road: once
    // there is no pavement there is nothing for them to fall on, and the frame
    // should be black.
    const poolMat = new THREE.MeshBasicMaterial({
        map: glowTexture,
        color: 0x9d7c48,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        fog: false,
    });
    const pools = [-1, 1].map((side) => {
        const pool = new THREE.Mesh(new THREE.PlaneGeometry(9, 30), poolMat);
        pool.rotation.x = -Math.PI / 2;
        // Far enough ahead to clear the hood's leading edge — nearer than this
        // and the car hides its own headlights. The near half being cut off by
        // the hood is correct: that is what the driver sees.
        pool.position.set(side * 2.4, 0.02, -20);
        return pool;
    });

    const lineMat = () =>
        new THREE.MeshBasicMaterial({ color: 0xe6e0d2, transparent: true });
    const edgeInner = new THREE.Mesh(
        new THREE.RingGeometry(inner - 0.4, inner, 192, 1),
        lineMat(),
    );
    const edgeOuter = new THREE.Mesh(
        new THREE.RingGeometry(outer, outer + 0.4, 192, 1),
        lineMat(),
    );
    edgeInner.rotation.x = edgeOuter.rotation.x = -Math.PI / 2;
    edgeInner.position.y = edgeOuter.position.y = 0.01;

    // Marker posts, just outside the outer edge. These are the "static
    // reference points passing by" the whole story turns on, so they get a
    // gold reflector band: at night that band is all you actually see, and it
    // is the same gold the lattice markers use later.
    const postRadius = outer + T.postOffsetFromEdge;
    const postGeo = new THREE.BoxGeometry(0.22, T.postHeight, 0.22);
    const bandGeo = new THREE.BoxGeometry(0.27, 0.3, 0.27);
    const postMat = new THREE.MeshBasicMaterial({ color: 0x39404d, transparent: true });
    const bandMat = new THREE.MeshBasicMaterial({
        color: 0xd8a94a,
        transparent: true,
        fog: false,
    });
    const posts = new THREE.InstancedMesh(postGeo, postMat, T.postCount);
    const bands = new THREE.InstancedMesh(bandGeo, bandMat, T.postCount);
    const m = new THREE.Matrix4();
    for (let i = 0; i < T.postCount; i++) {
        const a = (i / T.postCount) * Math.PI * 2;
        const x = Math.sin(a) * postRadius;
        const z = Math.cos(a) * postRadius;
        m.makeTranslation(x, T.postHeight / 2, z);
        posts.setMatrixAt(i, m);
        m.makeTranslation(x, T.postHeight - 0.15, z);
        bands.setMatrixAt(i, m);
    }
    posts.frustumCulled = bands.frustumCulled = false;

    grass.renderOrder = 0;
    pavement.renderOrder = 1;
    edgeInner.renderOrder = edgeOuter.renderOrder = 2;
    posts.renderOrder = bands.renderOrder = 3;
    trackRoot.add(grass, pavement, edgeInner, edgeOuter, posts, bands);

    /* --- the car, held in the car frame --------------------------------- */
    const car = new THREE.Group();
    car.matrixAutoUpdate = false;

    // Almost a silhouette. At night from inside the car you get the cowl
    // filling the bottom of the frame, a strip of hood below the horizon, and
    // two fender rails converging on the vanishing point — which is the whole
    // reason the shot works: those rails are the only thing in beats 2 and 3
    // still telling you which way is forward.
    const shell = new THREE.MeshBasicMaterial({ color: 0x0a0d13, transparent: true });
    // A shade off the sky rather than equal to it, so the hood reads as a
    // surface catching a little sky rather than as a hole in the frame.
    const hoodMat = new THREE.MeshBasicMaterial({ color: 0x10161f, transparent: true });
    const trim = new THREE.MeshBasicMaterial({ color: 0x141920, transparent: true });
    const edge = new THREE.MeshBasicMaterial({ color: 0x55637a, transparent: true });
    // The one warm line in the car, and the same gold as the post reflectors and
    // the lattice markers. Two of these run the length of the fenders: in beats
    // 2 and 3, once the grass, the posts and finally the road have all gone,
    // they are the only thing left in frame telling you which way is forward.
    const crease = new THREE.MeshBasicMaterial({ color: 0x1d2531, transparent: true });
    const pinstripe = new THREE.MeshBasicMaterial({
        color: 0xb08a3e,
        transparent: true,
        fog: false,
    });

    const part = (w, h, d, x, y, z, mat) => {
        const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
        mesh.position.set(x, y, z);
        return mesh;
    };

    const bodyParts = [
        part(2.05, 0.55, 0.55, 0, 0.4, -0.42, shell), // cowl
        part(1.9, 0.1, 2.7, 0, 0.72, -2.0, hoodMat), // hood
        part(0.09, 0.02, 2.6, 0, 0.78, -2.05, crease), // centre crease
        part(1.3, 0.08, 0.5, 0, 0.74, -3.55, hoodMat), // nose
        part(0.12, 0.1, 2.6, -0.88, 0.73, -2.1, edge), // left fender rail
        part(0.12, 0.1, 2.6, 0.88, 0.73, -2.1, edge), // right fender rail
        part(0.05, 0.015, 2.6, -0.88, 0.785, -2.1, pinstripe), // left pinstripe
        part(0.05, 0.015, 2.6, 0.88, 0.785, -2.1, pinstripe), // right pinstripe
        part(1.8, 0.07, 0.28, 0, 1.62, -0.3, trim), // windshield header
        part(0.07, 0.55, 0.3, -0.84, 1.33, -0.3, trim), // A-pillar left
        part(0.07, 0.55, 0.3, 0.84, 1.33, -0.3, trim), // A-pillar right
    ];

    // The hood ornament: a mount, a gold ring, and the little globe that the
    // camera pushes into at the end of beat 4. Its size and position are the
    // numbers the match cut is built on — do not adjust one without the other.
    const stalk = new THREE.Mesh(
        new THREE.CylinderGeometry(0.016, 0.026, 0.36, 12),
        edge,
    );
    stalk.position.set(0, 0.945, -1.5);

    const ring = new THREE.Mesh(
        new THREE.TorusGeometry(T.ornamentGlobeRadius * 1.28, 0.008, 8, 40),
        new THREE.MeshBasicMaterial({ color: 0xd8a94a, transparent: true, fog: false }),
    );
    ring.position.copy(T.ornamentGlobeCenter);
    ring.rotation.x = Math.PI / 2.4;

    const globeMat = new THREE.MeshBasicMaterial({
        map: earthTexture,
        transparent: true,
        fog: false,
    });
    const globe = new THREE.Mesh(
        new THREE.SphereGeometry(T.ornamentGlobeRadius, 40, 28),
        globeMat,
    );
    globe.position.copy(T.ornamentGlobeCenter);

    car.add(...bodyParts, stalk, ring, globe, ...pools);
    car.traverse((o) => {
        if (o.isMesh) o.renderOrder = 5;
    });
    trackRoot.add(car);

    targets.grass = fadeTarget([grass.material]);
    targets.posts = fadeTarget([postMat, bandMat]);
    targets.trackEdgeLines = fadeTarget([edgeInner.material, edgeOuter.material]);
    targets.trackPavement = {
        pavement: fadeTarget([pavement.material]),
        pools: fadeTarget([poolMat], { additive: true }),
        set(v) {
            this.pavement.set(v);
            this.pools.set(v);
        },
    };
    targets.car = fadeTarget([shell, hoodMat, trim, edge, crease, pinstripe, ring.material]);
    targets.ornamentGlobe = fadeTarget([globeMat]);

    return { car, globe };
}

/* -----------------------------------------------------------------------------
   The heliocentric world
   -------------------------------------------------------------------------- */
function buildSpace() {
    /* --- Sun ------------------------------------------------------------- */
    const sunMat = new THREE.MeshBasicMaterial({ color: 0xffe2ad, fog: false });
    const sun = new THREE.Mesh(
        new THREE.SphereGeometry(T.sunRadius, 48, 32),
        sunMat,
    );
    const glowMat = new THREE.SpriteMaterial({
        map: glowTexture,
        color: 0xffc978,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        fog: false,
    });
    const glow = new THREE.Sprite(glowMat);
    glow.scale.setScalar(T.sunRadius * 11);

    // decay 0: this is a stylized solar system, not a photometric one, and a
    // physical falloff over 60 units would leave the Earth unlit.
    const sunLight = new THREE.PointLight(0xfff4e2, 5.2, 0, 0);
    const ambient = new THREE.AmbientLight(0x2a3448, 0.7);

    /* --- Earth ----------------------------------------------------------- */
    const earthMat = new THREE.MeshStandardMaterial({
        map: earthTexture,
        roughness: 0.95,
        metalness: 0,
        transparent: true,
        fog: false,
    });
    const earth = new THREE.Mesh(
        new THREE.SphereGeometry(T.earthRadius, 64, 48),
        earthMat,
    );
    // A tilted spin axis carried on a parent, so the texture longitude offset
    // and the tilt do not fight each other.
    const earthAxis = new THREE.Group();
    earthAxis.rotation.z = THREE.MathUtils.degToRad(T.earthAxialTiltDegrees);
    earthAxis.add(earth);

    // From beat 6 onward the camera sits behind the Earth, looking sunward, so
    // the disc facing it is entirely night. A fresnel shell gives that disc a
    // lit rim — which is both what a backlit planet actually looks like and the
    // only reason the Earth stays legible for the rest of the story.
    const atmoMat = new THREE.ShaderMaterial({
        uniforms: {
            uColor: { value: new THREE.Color(0x7db4ff) },
            uOpacity: { value: 0 },
        },
        vertexShader: `
            varying vec3 vNormalView;
            varying vec3 vToEye;
            void main() {
                vec4 mv = modelViewMatrix * vec4(position, 1.0);
                vNormalView = normalize(normalMatrix * normal);
                vToEye = normalize(-mv.xyz);
                gl_Position = projectionMatrix * mv;
            }
        `,
        fragmentShader: `
            uniform vec3 uColor;
            uniform float uOpacity;
            varying vec3 vNormalView;
            varying vec3 vToEye;
            void main() {
                float rim = pow(
                    1.0 - abs(dot(normalize(vNormalView), normalize(vToEye))),
                    3.2
                );
                float a = rim * uOpacity;
                if (a < 0.004) discard;
                gl_FragColor = vec4(uColor, a);
            }
        `,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        side: THREE.BackSide,
    });
    const atmosphere = new THREE.Mesh(
        new THREE.SphereGeometry(T.earthRadius * 1.12, 48, 32),
        atmoMat,
    );
    earthAxis.add(atmosphere);

    // The home marker: where you are, on a globe you are looking at from
    // outside. A gold pip, the same gold as everything else that marks a place.
    const homeMat = new THREE.SpriteMaterial({
        map: glowTexture,
        color: 0xffd98a,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        opacity: 0,
        fog: false,
    });
    const home = new THREE.Sprite(homeMat);
    home.scale.setScalar(T.earthRadius * 0.34);
    // Roughly San Francisco on the stylized texture.
    const lat = THREE.MathUtils.degToRad(37.77);
    const lon = THREE.MathUtils.degToRad(-122.4 - T.earthTextureLongitudeOffsetDegrees);
    const homeR = T.earthRadius * 1.01;
    home.position.set(
        Math.cos(lat) * Math.cos(lon) * homeR,
        Math.sin(lat) * homeR,
        -Math.cos(lat) * Math.sin(lon) * homeR,
    );
    earth.add(home);

    /* --- Orbit path ------------------------------------------------------- */
    const orbitPts = [];
    for (let i = 0; i <= T.orbitSegmentCount; i++) {
        const a = (i / T.orbitSegmentCount) * Math.PI * 2;
        orbitPts.push(
            Math.cos(a) * T.orbitRadius,
            0,
            Math.sin(a) * T.orbitRadius,
        );
    }
    const orbitGeo = new THREE.BufferGeometry();
    orbitGeo.setAttribute(
        "position",
        new THREE.BufferAttribute(new Float32Array(orbitPts), 3),
    );
    const orbitMat = revealMaterial({
        mode: 2,
        color: 0xd8a94a,
        soft: 0.16,
        opacity: 0.85,
    });
    const orbit = new THREE.Line(orbitGeo, orbitMat);
    orbit.frustumCulled = false;

    /* --- The grid laid over the orbital plane ---------------------------- */
    const gridMat = revealMaterial({
        mode: 0,
        color: 0x4f7fbe,
        soft: 9,
        opacity: 0.4,
    });
    const grid = new THREE.LineSegments(buildGridGeometry(), gridMat);
    grid.frustumCulled = false;

    /* --- The markers ------------------------------------------------------ */
    const nodeMat = revealMaterial({
        mode: 1,
        color: 0xe8be6a,
        soft: 22,
        opacity: 0.95,
    });
    const nodes = new THREE.LineSegments(buildNodeGeometry(), nodeMat);
    nodes.frustumCulled = false;

    spaceRoot.add(sun, glow, sunLight, ambient, earthAxis, orbit, grid, nodes);

    targets.sun = fadeTarget([sunMat, glowMat], { additive: true });
    const earthFade = fadeTarget([earthMat]);
    targets.earth = {
        set(v) {
            earthFade.set(v);
            atmoMat.uniforms.uOpacity.value = v;
            atmosphere.visible = v > 0.002;
        },
    };
    targets.homeMarker = fadeTarget([homeMat], { additive: true });
    targets.orbitPath = revealTarget(orbitMat, Math.PI * 2, 0.16);
    targets.spaceGrid = revealTarget(gridMat, T.gridExtent * 1.45, 9);
    targets.gridNodes = revealTarget(nodeMat, T.gridExtent * 2.3, 22);

    return { earth, earthAxis, orbitMat, nodeMat };
}

/** Grid lines in the orbital plane, on the lattice's own spacing. */
function buildGridGeometry() {
    const s = T.gridSpacing;
    const n = Math.floor(T.gridExtent / s);
    const pts = [];
    for (let i = -n; i <= n; i++) {
        for (let j = -n; j < n; j++) {
            // Broken into one segment per cell so the radial reveal has
            // something to bite on — a full-length line would pop in whole.
            pts.push(i * s, 0, j * s, i * s, 0, (j + 1) * s);
            pts.push(j * s, 0, i * s, (j + 1) * s, 0, i * s);
        }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute(
        "position",
        new THREE.BufferAttribute(new Float32Array(pts), 3),
    );
    return g;
}

/** The markers themselves: wireframe cubes on the lattice points. */
function buildNodeGeometry() {
    const s = T.gridSpacing;
    const n = Math.floor(T.gridExtent / s);
    const h = (s * T.nodeCubeEdgeFraction) / 2;
    const layers = [-s, 0, s]; // three sheets, so the lattice has depth
    const pts = [];

    // The twelve edges of a cube, as index pairs into its eight corners.
    const corner = (i) => [i & 1 ? h : -h, i & 2 ? h : -h, i & 4 ? h : -h];
    const edges = [
        [0, 1], [2, 3], [4, 5], [6, 7],
        [0, 2], [1, 3], [4, 6], [5, 7],
        [0, 4], [1, 5], [2, 6], [3, 7],
    ];

    for (const y of layers) {
        for (let i = -n; i <= n; i++) {
            for (let j = -n; j <= n; j++) {
                const x = i * s;
                const z = j * s;
                const r = Math.hypot(x, z);
                // Nothing inside the Sun, nothing past the disc's edge.
                if (r < T.sunRadius * 2.6 || r > T.gridExtent) continue;
                for (const [a, b] of edges) {
                    const ca = corner(a);
                    const cb = corner(b);
                    pts.push(x + ca[0], y + ca[1], z + ca[2]);
                    pts.push(x + cb[0], y + cb[1], z + cb[2]);
                }
            }
        }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute(
        "position",
        new THREE.BufferAttribute(new Float32Array(pts), 3),
    );
    return g;
}

const track = buildTrack();
const space = buildSpace();

/* =============================================================================
   Beat state

   Actions are replayed from the first beat every frame rather than accumulated,
   which is what makes scrubbing backwards work: at any scroll position the
   scene is a pure function of (beat, progress), with no history to unwind.
   ============================================================================= */

/* Sweep origins are captured the first time their beat is entered, so the orbit
   draws itself from under the Earth and the markers sweep out from beneath it,
   wherever in its orbit the Earth happens to be when you scroll that far. */
const sweepOrigin = { orbitAngle: null, nodeCenter: new THREE.Vector3() };

function applyBeatState(index, p) {
    const state = { ...INITIAL };
    const progressOf = { orbitPath: 0, spaceGrid: 0, gridNodes: 0 };

    for (let b = 0; b <= index; b++) {
        for (const a of BEATS[b].actions) {
            const u =
                b < index
                    ? 1
                    : smoothstep(a.range[0], a.range[1], p);
            if (a.effect === "fade") {
                state[a.target] = lerp(a.from, a.to, u);
            } else {
                state[a.target] = u;
                progressOf[a.target] = u;
            }
        }
    }

    for (const [name, value] of Object.entries(state)) {
        targets[name]?.set(value);
    }
    return progressOf;
}

/* =============================================================================
   Scroll wiring
   ============================================================================= */

const storyEl = document.getElementById("story");
const beatEls = Array.from(document.querySelectorAll(".beat"));
const railFill = document.getElementById("rail-fill");
const rail = document.getElementById("rail");
const stage = document.getElementById("stage");

beatEls.forEach((el) => el.style.setProperty("--span", el.dataset.span));

// Normalized [start, end] of each beat within the story's scroll range, filled
// in by measure(). The story's tail is exactly one viewport tall, which makes
// that range equal to the summed beat heights — see index.html.
const windows = [];
let storyScrollLength = 1;

function measure() {
    const heights = beatEls.map((el) => el.offsetHeight);
    storyScrollLength = heights.reduce((a, b) => a + b, 0);
    let cum = 0;
    heights.forEach((h, i) => {
        windows[i] = [cum / storyScrollLength, (cum + h) / storyScrollLength];
        cum += h;
    });
}
measure();

// GSAP drives one scalar; everything else is derived from it in the render
// loop. ScrollTrigger owns the scroll math, Lenis owns the feel.
const scrub = { p: 0 };
gsap.to(scrub, {
    p: 1,
    ease: "none",
    scrollTrigger: {
        trigger: storyEl,
        start: "top top",
        end: () => "+=" + storyScrollLength,
        scrub: true,
        invalidateOnRefresh: true,
        onRefresh: measure,
    },
});

// Hand the page over to the content: dim the stage, retire the rail.
ScrollTrigger.create({
    trigger: "#content",
    start: "top 85%",
    onEnter: () => {
        stage.style.opacity = "0.3";
        rail.style.opacity = "0";
    },
    onLeaveBack: () => {
        stage.style.opacity = "1";
        rail.style.opacity = "1";
    },
});

// Content sheets and the story's closing line rise as they arrive.
const io = new IntersectionObserver(
    (entries) => {
        entries.forEach((e) => {
            if (e.isIntersecting) {
                e.target.classList.add("in");
                io.unobserve(e.target);
            }
        });
    },
    { threshold: 0.15 },
);
document
    .querySelectorAll(".sheet, .tail-line")
    .forEach((el) => io.observe(el));

let lenis = null;
if (!reduceMotion) {
    lenis = new Lenis({ lerp: 0.09, wheelMultiplier: 1 });
    lenis.on("scroll", ScrollTrigger.update);
    gsap.ticker.add((time) => lenis.raf(time * 1000));
    gsap.ticker.lagSmoothing(0);
}

/* A handle for jumping straight to a point in the story, by beat name or by
   overall progress. Smooth scrolling means window.scrollTo is a request rather
   than an instruction, so anything checking a specific frame — a screenshot
   pass, or a person looking at beat seven without scrolling to it — needs a way
   to land exactly. Costs nothing and saves rebuilding it every time. */
window.__firmament = {
    beats: BEATS.map((b) => b.id),
    get progress() {
        return scrub.p;
    },
    seek(progress) {
        const y = storyEl.offsetTop + clamp01(progress) * storyScrollLength;
        if (lenis) lenis.scrollTo(y, { immediate: true, force: true });
        else window.scrollTo(0, y);
        ScrollTrigger.update();
        return scrub.p;
    },
    seekBeat(id, local = 0.5) {
        const i = BEATS.findIndex((b) => b.id === id);
        if (i < 0) return null;
        const [a, b] = windows[i];
        return this.seek(lerp(a, b, local));
    },
};

/* =============================================================================
   Render
   ============================================================================= */

function resize() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    // Cap the pixel ratio: at this scene's density the extra samples buy
    // nothing on a phone and cost a great deal.
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, w < 700 ? 1.5 : 2));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
}
window.addEventListener("resize", () => {
    resize();
    measure();
    ScrollTrigger.refresh();
});
resize();

/** Resolve one keyframe into a world-space pose at scene time `t`. */
const _m = new THREE.Matrix4();
function resolve(kf, t) {
    _m.copy(frameFor(kf.frame, t));
    return {
        position: kf.position.clone().applyMatrix4(_m),
        lookAt: kf.lookAt.clone().applyMatrix4(_m),
        fov: kf.fov,
    };
}

/** Place the camera for beat `index` at beat progress `p`. */
const _look = new THREE.Vector3();
function updateCamera(index, p, t) {
    const keys = BEATS[index].camera;
    let i = 0;
    while (i < keys.length - 2 && keys[i + 1].progress < p) i++;

    const a = resolve(keys[i], t);
    const b = resolve(keys[Math.min(i + 1, keys.length - 1)], t);
    const u = smoothstep(keys[i].progress, keys[Math.min(i + 1, keys.length - 1)].progress, p);

    camera.position.lerpVectors(a.position, b.position, u);
    _look.lerpVectors(a.lookAt, b.lookAt, u);
    camera.lookAt(_look);

    const fov = lerp(a.fov, b.fov, u);
    if (Math.abs(camera.fov - fov) > 1e-4) {
        camera.fov = fov;
        camera.updateProjectionMatrix();
    }
}

/** Fade a beat's copy in as it takes over and out as it hands off. */
function updatePanels(index, p) {
    if (reduceMotion) return;
    beatEls.forEach((el, i) => {
        const panel = el.firstElementChild;
        let o = 0;
        let dy = 0;
        if (i === index) {
            // The opening beat is already on screen at load — no fade-in.
            const enter = i === 0 ? 1 : smoothstep(0.02, 0.2, p);
            const exit = 1 - smoothstep(0.78, 0.96, p);
            o = enter * exit;
            dy = (1 - enter) * 20 - (1 - exit) * 20;
        }
        panel.style.opacity = o.toFixed(3);
        panel.style.transform = `translateY(calc(-50% + ${dy.toFixed(1)}px))`;
    });
}

const startTime = performance.now() / 1000;
let lastBeat = -1;

function frame() {
    // Idle motion runs on wall-clock time, so the reference points keep
    // streaming past even when the reader has stopped scrolling. Under reduced
    // motion the clock is frozen and only scroll moves anything.
    const t = reduceMotion ? 0 : performance.now() / 1000 - startTime;

    const p = clamp01(scrub.p);
    let index = windows.findIndex(([s, e]) => p < e);
    if (index < 0) index = BEATS.length - 1;
    const [s, e] = windows[index];
    const local = spanProgress(p, s, e);

    const beat = BEATS[index];
    trackRoot.visible = beat.world === "track";
    spaceRoot.visible = beat.world === "space";
    scene.fog = beat.world === "track" ? trackFog : null;

    // Capture each sweep's origin the first time its beat is reached, so the
    // orbit draws on from under the Earth and the markers sweep out from it.
    if (index !== lastBeat) {
        const pose = earthPose(t);
        if (beat.id === "orbitDrawn") {
            sweepOrigin.orbitAngle = pose.angle;
        } else if (beat.id === "nodesAppear") {
            sweepOrigin.nodeCenter.copy(pose.position);
        }
        lastBeat = index;
    }
    space.orbitMat.uniforms.uStartAngle.value =
        sweepOrigin.orbitAngle ?? earthPose(t).angle;
    space.nodeMat.uniforms.uCenter.value.copy(sweepOrigin.nodeCenter);

    // The car rides its frame; the Earth rides its orbit and spins on its axis.
    track.car.matrix.copy(frameFor("car", t));
    const earthAt = earthPose(t);
    space.earthAxis.position.copy(earthAt.position);
    space.earth.rotation.y =
        THREE.MathUtils.degToRad(T.earthTextureLongitudeOffsetDegrees) +
        (t / T.earthSpinSecondsPerRevolution) * Math.PI * 2;

    applyBeatState(index, local);
    updateCamera(index, local, t);
    updatePanels(index, local);

    railFill.style.height = (p * 100).toFixed(2) + "%";

    renderer.render(scene, camera);
}

renderer.setAnimationLoop(frame);

// The first frame decides whether the hero reads at all, so do not wait for the
// scroll libraries to settle before drawing it.
ScrollTrigger.refresh();
