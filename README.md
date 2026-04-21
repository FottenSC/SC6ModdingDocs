# SoulCalibur VI Modding Docs

Reverse-engineering notes for **SoulCalibur VI**, written primarily as a
knowledge base for AI coding agents working on mods via
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS).

Pages are auto-generated from Ghidra analysis of the shipping Steam binary
(class layouts, function RVAs, struct offsets, UFunction trampolines) and
cross-checked against live UE4SS runtime introspection. Content is written
for machine readers first — dense, offset-accurate, with explicit source
citations — and stays readable to humans as a side effect.

Built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/).
Every page is plain Markdown under `docs/`. To add a page:

1. Create `docs/<section>/<page>.md`
2. Add it to `nav:` in `mkdocs.yml`
3. Commit — Cloudflare Pages rebuilds and redeploys automatically

See [`docs/contributing.md`](docs/contributing.md) for the full (short)
guide — including the rules AI agents should follow when adding pages.

## Local preview

```bash
# With uv (matches the Cloudflare build — fastest):
uv pip install -r requirements.txt
mkdocs serve

# Or plain pip:
pip install -r requirements.txt
mkdocs serve
# open http://127.0.0.1:8000
```

## Deployment — Cloudflare Pages

No CI config is needed in this repo. Cloudflare Pages watches the GitHub repo and builds on every
push to `main` (and produces a preview URL for every other branch / PR).

One-time setup in the Cloudflare dashboard — **Workers & Pages → Create → Pages → Connect to Git**:

| Setting | Value |
|---|---|
| Framework preset | *None* |
| Build command | `pip install uv && uv pip install --system -r requirements.txt && mkdocs build --strict` |
| Build output directory | `site` |
| Root directory | *(leave blank)* |
| Environment variable | `PYTHON_VERSION` = `3.12` |

You'll get a `*.pages.dev` URL after the first build. Add a custom domain under the project's
**Custom domains** tab if desired.

> **Why `uv`?** The naïve `pip install -r requirements.txt` takes ~90s on Cloudflare Pages
> (serial resolver + building `regex` from source). `uv` resolves in parallel and prefers
> pre-built wheels, cutting the install step to ~5s. `mkdocs build` itself is sub-second,
> so the whole Cloudflare deploy drops from ~3 min to ~30s. A curl-install variant works
> too if you'd rather skip the `pip install uv` bootstrap:
>
> ```bash
> curl -LsSf https://astral.sh/uv/install.sh | sh \
>   && $HOME/.local/bin/uv pip install --system -r requirements.txt \
>   && mkdocs build --strict
> ```

### Why no GitHub Actions?

Cloudflare Pages does the build itself when it detects a push — adding a GH Actions workflow would
just duplicate that work. If you ever want to mirror to GitHub Pages as a backup, add a workflow
back then.

## License / disclaimer

Community project. Not affiliated with BANDAI NAMCO or the UE4SS team.
