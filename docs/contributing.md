# Contributing

This site is deliberately easy to extend — it's just Markdown and one YAML file. That makes it
friendly for both human contributors and AI agents.

## Add a new page (the 30-second version)

1. Create a new `.md` file under `docs/` in the right folder (e.g. `docs/cookbook/swap-mesh.md`).
2. Add it to the `nav:` list in `mkdocs.yml` (at the repo root) so it shows up in the sidebar.
3. Open a PR. Cloudflare Pages builds and redeploys on merge to `main`; every other branch / PR gets its own preview URL.

That's the whole workflow. You do **not** need to know JavaScript, React, Vue, or Astro.

## Rules of thumb for AI agents

When an AI agent is adding or editing pages, it should:

- **Prefer Markdown primitives** — tables, fenced code blocks, bullet lists — over custom HTML.
- **Use admonitions** for non-prose content:
  ```
  !!! warning "Title"
      Body text.
  ```
  Supported: `note`, `tip`, `info`, `warning`, `danger`, `example`, `question`, `success`, `failure`.
- **Label code fences** with a language (`lua`, `cpp`, `ini`, `json`, `text`) so syntax highlighting works.
- **Link relatively** between pages (`../ue4ss/hooks.md`), never absolute URLs for in-site links.
- **Keep page titles as H1** at the top of the file (`# Title`).
- **Update `mkdocs.yml` `nav:`** whenever you add a new page — otherwise it's orphaned.
- **Stub pages are fine**: add an `!!! info "Stub"` admonition and a TODO list so future passes know where to expand.
- **Cite the source** of reversed info (dumper output, hook trace, disasm at address, etc.) in a `> source:` blockquote beneath the claim.

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
