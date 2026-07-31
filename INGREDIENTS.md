# Build ingredients

Everything baked into the shipped `.pkg`, and how a change to it reaches a release. An *ingredient* is
an input to the product; the *own upstream* is the thing a repo exists to port.

**This repo has no single own upstream.** It assembles several independent docker components, so its
version is date-based (`<date>-mavericks.N`) and its repackage caller runs with
`own-upstream-paths: ""` — every pin under `components/` is an ingredient, and any of them moving is a
repackage of the same date-stamped product.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| docker CLI | `components/docker-cli/version` (`REPO=` + `REF=` + `DIGEST=`) | ✅ `git-refs` + `currentDigest` | watched path → repackage dispatched → `-mavericks.(N+1)` |
| docker Compose | `components/docker-compose/version` | ✅ `git-refs` + `currentDigest` | same |
| docker Machine | `components/docker-machine/version` | ✅ `git-refs` + `currentDigest` | same |
| lazydocker | `components/lazydocker/version` | ✅ `git-refs` + `currentDigest` | same |
| boot2docker source | `components/boot2docker/version` | ✅ `git-refs` + `currentDigest` | same; the iso build re-clones (commit-digest-verified) + rebuilds |
| boot2docker patch overlay | `components/boot2docker/patches/*.patch` | n/a (this repo's own fix) | **is** an ingredient — it is applied into the iso, so a change rebuilds it |
| ModernMavericks Go cross toolchain | `components/golang/version` | ✅ `github-releases` on `ModernMavericks/golang` | watched path → repackage rebuilt on the new Go |
| MacOSX10.9 SDK, Sparkle framework | `ModernMavericks/shared-cmake@v1` | ✅ github-actions manager tracks the tag | `@v1` is a *moving* tag: content changes without the pin changing, so nothing auto-repackages |

Not ingredients: `cmake/`, `menubar/`, `payload/`, and the updater are this repo's own recipe. A change
there is a repackage you cut deliberately (`workflow_dispatch` with `local_release=true`).

## Why the patch counts as an ingredient

`cmake/build_boot2docker.sh` applies every `components/boot2docker/patches/*.patch` into the iso build,
so a patch edit changes the shipped product exactly as a version bump would. The caller watches
`components/**`, which covers it — and generated release notes describe a patch by its subject line and
line delta rather than a meaningless byte count.

## Acceptance is manual for the iso

CI proves the build and the fetch/fingerprint gates; a modern runner cannot boot-proof the iso, so the
boot-proof auto-skips (`ctest` code 77). Real-10.9 boot testing is the acceptance bar — do not read a
green CI as proof the iso boots.
