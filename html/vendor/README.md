# Vendored libraries

Checked in rather than pulled from a CDN: `make deploy-html` is an rsync of this
directory to a plain static host, there is no build step, and a page that draws
its own hero has no business failing because someone else's edge node is having
a bad day. Nothing here is modified from the published build.

| File | Version | License |
| --- | --- | --- |
| `three.module.min.js` | three.js 0.169.0 | MIT |
| `gsap.min.js` | GSAP 3.12.5 | GreenSock Standard License (free for this use) |
| `ScrollTrigger.min.js` | GSAP 3.12.5 | GreenSock Standard License |
| `lenis.min.js` | Lenis 1.1.18 | MIT |

three.js is an ES module and is reached through the import map in `index.html`;
the other three are plain scripts that attach `gsap`, `ScrollTrigger` and
`Lenis` to the window.

To update, replace the file and check the beats still land:

    curl -L -o vendor/three.module.min.js https://unpkg.com/three@<v>/build/three.module.min.js
    curl -L -o vendor/gsap.min.js         https://unpkg.com/gsap@<v>/dist/gsap.min.js
    curl -L -o vendor/ScrollTrigger.min.js https://unpkg.com/gsap@<v>/dist/ScrollTrigger.min.js
    curl -L -o vendor/lenis.min.js        https://unpkg.com/lenis@<v>/dist/lenis.min.js
