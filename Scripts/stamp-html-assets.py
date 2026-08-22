#!/usr/bin/env python3
"""Stamp every local asset link in an HTML directory with a hash of the file
it points at, so the URL changes whenever the file's contents do.

akuaku.org sits behind Cloudflare, which caches static assets by URL for four
hours. Redeploying `firmament.css` under an unchanged name therefore leaves
visitors on the old copy until the TTL lapses — the landing page went out once
with its new markup and its previous stylesheet for exactly that reason, which
looks like a broken page rather than a stale one. A content hash in the query
string makes a changed file a different URL, which no cache can confuse for the
old one, and leaves an unchanged file's URL alone so its cache still counts.

Rewrites in place and is idempotent: running it twice changes nothing. `make
deploy-html` runs it first; run `make stamp-html` by hand to see the diff before
committing.

    stamp-html-assets.py html [...]
"""

import hashlib
import pathlib
import re
import sys

# Any quoted, relative path to a file we serve ourselves — which covers href=,
# src=, the import map's module specifiers and og:image alike, and skips the
# inline data: favicon, absolute URLs and anything with a fragment, none of
# which match.
LINK = re.compile(
    r'(?<=")((?:\./)?[\w.\-/]+\.(?:css|js|mjs|png|jpe?g|svg|webp|woff2?))'
    r'(?:\?v=[0-9a-f]+)?(?=")'
)


def rewrite(source: pathlib.Path, base: pathlib.Path, root: pathlib.Path) -> bool:
    """Stamp the links in one file. `base` is what its relative paths resolve
    against; `root` bounds what counts as ours."""
    before = source.read_text(encoding="utf-8")

    def replace(match: re.Match) -> str:
        link = match.group(1)
        target = (base / link).resolve()
        # Leave anything we do not actually ship untouched rather than stamping
        # a URL that resolves somewhere else.
        if not target.is_file() or root not in target.parents:
            return match.group(0)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()[:8]
        return f"{link}?v={digest}"

    after = LINK.sub(replace, before)
    if after == before:
        return False
    source.write_text(after, encoding="utf-8")
    print(f"  stamped {source}")
    return True


def stamp(directory: pathlib.Path) -> int:
    root = directory.resolve()
    changed = 0

    # Scripts first. A URL inside a module resolves against the document that
    # loaded it, not against the module — so js/story.js asking for
    # "assets/earth-stylized.png" means html/assets/earth-stylized.png. Doing
    # these first is what makes the cascade work: stamping the texture changes
    # story.js, which changes the hash the HTML has to carry for it.
    for script in sorted(p.resolve() for p in directory.rglob("*.js")):
        if "vendor" in script.relative_to(root).parts:
            continue  # third-party bundles reference nothing of ours
        changed += rewrite(script, root, root)

    for page in sorted(p.resolve() for p in directory.rglob("*.html")):
        changed += rewrite(page, page.parent, root)

    return changed


def main() -> int:
    directories = [pathlib.Path(a) for a in sys.argv[1:]] or [pathlib.Path("html")]
    for directory in directories:
        if not directory.is_dir():
            print(f"✗ {directory} is not a directory", file=sys.stderr)
            return 1
    total = sum(stamp(d) for d in directories)
    print(f"✓ asset links stamped ({total} file(s) rewritten)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
