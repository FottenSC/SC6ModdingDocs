# SoulCalibur VI Modding Docs

Community documentation for modding **SoulCalibur VI** via the
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) framework.

Built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/). Every page is plain
Markdown under `docs/`. To add a page:

1. Create `docs/<section>/<page>.md`
2. Add it to `nav:` in `mkdocs.yml`
3. Commit → Cloudflare Pages rebuilds and redeploys automatically

See [`docs/contributing.md`](docs/contributing.md) for the full (short) guide — including the rules
AI agents should follow when adding pages.

## Local preview

```bash
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
| Build command | `pip install -r requirements.txt && mkdocs build --strict` |
| Build output directory | `site` |
| Root directory | *(leave blank)* |
| Environment variable | `PYTHON_VERSION` = `3.12` |

You'll get a `*.pages.dev` URL after the first build. Add a custom domain under the project's
**Custom domains** tab if desired.

### Why no GitHub Actions?

Cloudflare Pages does the build itself when it detects a push — adding a GH Actions workflow would
just duplicate that work. If you ever want to mirror to GitHub Pages as a backup, add a workflow
back then.

## License / disclaimer

Community project. Not affiliated with BANDAI NAMCO or the UE4SS team.
