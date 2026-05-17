# Contributing

This site is deliberately easy to extend — it's just Markdown plus one YAML file, which makes it
friendly for both human contributors and AI agents.

## Add a new page (the 30-second version)

1. Create a new `.md` file under `docs/` in the right folder (e.g. `docs/cookbook/swap-mesh.md`).
2. Add it to the `nav:` list in `mkdocs.yml` (at the repo root) so it appears in the sidebar.
3. Open a PR. Cloudflare Pages builds and redeploys on merge to `main`; every other branch and PR gets its own preview URL.

That's the whole workflow. You do **not** need to know JavaScript, React, Vue, or Astro.

## Rules of thumb for AI agents

### Reading the docs

Before adding or editing, an AI agent should know how to find existing content:

- **Have a symbol or offset?** [Symbol Index](reference/symbol-index.md) is the cross-cutting cheat sheet.
- **Have a topic?** Each domain has a landing page — see [SC6 internals index](sc6/index.md).
- **Honour status markers**: `verified` is trustworthy; `unverified` is a hypothesis; `stale on this build` means the codepath exists but isn't reached. Don't promote `unverified` to fact without re-checking against Ghidra.
- **`> source:` blockquotes** point at the Ghidra address whose plate-comment or decompile is authoritative. When a topic page disagrees with its source-of-record, re-read the source to settle it.
- **Conventions** for offset notation (`chara+0xN`, `BM+0xN`, `vmCtx+0xN`, `InputLog+0xN`) are listed in [SC6 index](sc6/index.md#conventions-used-on-these-pages).

### Editing the docs

When an AI agent is adding or editing pages, it should:

- **Prefer Markdown primitives** — tables, fenced code blocks, bullet lists — over custom HTML.
  Data is easier to extract from a table than from prose, for both humans and other AIs.
- **One fact per row** in tables — easier to grep, easier to update, easier to cross-reference.
- **Use admonitions** for non-prose content:
  ```
  !!! warning "Title"
      Body text.
  ```
  Supported: `note`, `tip`, `info`, `warning`, `danger`, `example`, `question`, `success`, `failure`.
- **Label code fences** with a language (`lua`, `cpp`, `ini`, `json`, `text`) so syntax highlighting works.
- **Link relatively** between pages (`../ue4ss/hooks.md`), never absolute URLs for in-site links.
- **Anchor links** must match the rendered slug — em-dashes (`—`) collapse, parentheses drop, backticks drop, spaces become `-`. When in doubt, check `site/<page>/index.html` after a build.
- **Keep page titles as H1** at the top of the file (`# Title`).
- **Update `mkdocs.yml` `nav:`** whenever you add a new page — otherwise it's orphaned.
- **Stub pages are fine**: add an `!!! info "Stub"` admonition and a TODO list so future passes know where to expand.
- **Cite the source** of reversed info (dumper output, hook trace, disasm at address, etc.) in a `> source:` blockquote beneath the claim.
- **Use status markers explicitly** when adding new claims: write "verified" or "unverified" — don't leave the reader (human or AI) to guess.
- **Don't duplicate facts** — link to the canonical page instead. If the same offset is documented in two places, one of them will go stale.
- **Update [Symbol Index](reference/symbol-index.md)** when adding a high-traffic symbol (a function called from multiple pages, a struct cited in multiple places). Skip for one-off references — they're better left to grep.

## Local preview (optional)

```bash
pip install -r requirements.txt
mkdocs serve
```

Open <http://127.0.0.1:8000> — the site live-reloads on save.

## Build

```bash
mkdocs build   # outputs to ./site
```

Cloudflare Pages runs the same command on every push — you rarely need to build locally unless you're debugging a `--strict` failure.
