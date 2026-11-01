---
name: curseforge-packaging
description: Set up, review or troubleshoot CurseForge automatic packaging for this WoW addon (webhook from GitHub, .pkgmeta, tag naming for alpha/beta/release, keyword substitution, @debug@/@do-not-package@/@alpha@ blocks, manual changelog, dependencies). Use when preparing a release, editing .pkgmeta, choosing a tag, or when a CurseForge package comes out wrong.
---

# CurseForge automatic packaging

Source: <https://support.curseforge.com/support/solutions/articles/9000197281-automatic-packaging> (page last modified 2024-02-21). Anything marked **not on that page** is from general knowledge of the packager and must be confirmed before relying on it.

## How a release happens

1. Create an API token at <https://www.curseforge.com/account/api-tokens>.
2. In the GitHub repo: Settings > Webhooks > Add webhook. Payload URL:
   `https://www.curseforge.com/api/projects/{projectID}/package?token={token}`
   Leave other settings at their defaults. `{projectID}` is shown under "About This Project" on the CurseForge project's Overview page.
3. Push. CurseForge packages from the repo.

**The token is a secret.** It lives only in the GitHub webhook settings. Never put the URL in a file, README, commit or chat that is public. The repo here is public.

## Release type comes from the tag name

- A pushed tag containing `alpha` (`1.0-alpha`, `1.0.alpha7`) is an **alpha**; containing `beta` is a **beta**; any other tag is a **release**.
- If the project is configured to package all commits, the latest untagged commit is packaged as an alpha.
- The page does not say whether the match is case-sensitive or what happens when both words appear: use lowercase and never both.
- Tag names are also what `@project-version@` expands to, so tag as the version (`v0.5.0` or `0.5.0`), consistent with `## Version:` in `CustomQuests.toc`.

## .pkgmeta (YAML, repo root, all fields optional)

Files named `.pkgmeta` or `pkgmeta.yaml`. Dotfiles/dot-directories and the pkgmeta file are always ignored.

```yaml
package-as: CustomQuests          # folder/package name (default: project URL slug)
enable-nolib-creation: no

externals:                        # libraries pulled from other repos
    libs/LibDialog:
        url: https://github.com/wildstarnasa/LibDialog.git
        tag: latest               # omit = latest version, even if not a tag

move-folders:                     # source: destination (sibling of the main folder)
    CustomQuests/Modules/Fire: CustomQuestsOnFire

ignore:                           # YAML list of files/folders left out of the zip
    - tests
    - tools

required-dependencies:            # CurseForge projects, "<id>-<slug>"
    - 221710-dear-cupcake
optional-dependencies:
    - 220002-junkit

manual-changelog: CHANGELOG.txt   # used instead of commit messages
license-output: LICENSE.txt       # include the project license
tools-used:
    - data-tools
```

This repo's `.pkgmeta` only uses `package-as` and `ignore` (tests, tools, docs, assets, SPEC.md, .luarc.json). It has no libraries, so no `externals`. Not on the page: `plain-copy`, `embedded-libraries`, and what `enable-nolib-creation` does.

**Check before every release**: everything the addon needs at runtime (the files in the TOC, `Media/Icon.tga`) must NOT be in `ignore`. Anything listed in `ignore` that the TOC loads breaks the addon.

## Keyword substitution (applied to text files in the package)

`@project-version@` (tag name on a tag, otherwise short revision), `@project-revision@`/`@project-hash@`, `@project-abbreviated-hash@`, `@project-author@`, `@project-date-iso@`, `@project-date-integer@`, `@project-timestamp@`, and the `@file-…@` equivalents per file (`@file-revision@`, `@file-abbreviated-hash@`, `@file-author@`, `@file-date-iso@`, `@file-date-integer@`, `@file-timestamp@`).

Not on the page: using `## Version: @project-version@` in a TOC. It is the usual practice, but it makes the TOC unreadable in the working copy; this repo keeps a literal version and `tools/build.py` reads it.

## Comment blocks

| Block | In the zip |
|---|---|
| `--@debug@` … `--@end-debug@` (Lua) | commented out in releases, kept in dev |
| `--@do-not-package@` … `--@end-do-not-package@` | removed completely (line numbers shift) |
| `--@alpha@` … `--@end-alpha@` | active only in alpha packages, commented out in beta/release |

XML uses `<!--@debug@-->` … `<!--@end-debug@-->`; TOC files use `#@debug@` … `#@end-debug@` (each line between gets a `#`). The tags must themselves sit inside comments so the file still runs unpackaged.

## Not covered by that page (verify elsewhere)

`## X-Curse-Project-ID` in the TOC, multi-client TOCs and suffixes (`_Mainline`, `_Classic`), TOC `## Interface` handling, localization, file size and count limits, branch filters, and the CurseForge/GitHub workflow alternative (BigWigs packager). Do not assert these as facts; look them up or ask.

## This project

- One package serves Retail and Forever: single `CustomQuests.toc` with `## Interface: 120105, 120001, 16001`, client detected by build number in `Compat/Common.lua`. No per-client TOCs or zips.
- Local equivalent for testing: `python tools/build.py` makes `dist/CustomQuests-<version>.zip` from the TOC's file list plus `Media/Icon.tga` and `README.md`. The CurseForge packager uses `.pkgmeta`, not this script, so both must stay in agreement: if you add a runtime file, put it in the TOC and make sure `.pkgmeta` does not ignore it.
- `luajit tests/run.lua` must pass before tagging; it also checks that the TOC lists both interfaces and every file exists.

## Release checklist

1. Tests pass; `## Version:` bumped; `CHANGELOG.md` has a new section at the top (this repo uses `manual-changelog` in `.pkgmeta`; the `markup-type` key is not on the CurseForge page, so confirm the first release shows the changelog correctly).
2. Webhook exists and points at the right project ID (the token is never committed).
3. Tag with the release type in the name when it is not a full release (`0.6.0-beta1`), plain `0.6.0` otherwise. Push the tag.
4. Download the produced zip and check: top folder is `CustomQuests`, TOC and every listed file present, `Media/Icon.tga` present, no `tests/`, `tools/`, `docs/`, `assets/`.
5. Test it on Retail and on Forever. Forever is still untested in game.
6. Do not publish a test or alpha tag from `main` accidentally: the webhook triggers on pushes.
