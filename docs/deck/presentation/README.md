# FunWithActivity — Architecture deck

A reveal.js 5 presentation built from `slides.md`.

## Run it

```bash
npm install
npm start
```

This serves the parent directory (`docs/deck`) as the web root, so open:

http://localhost:8422/presentation/

(Port 8422 rather than the http-server default of 8000, since 8000 is
frequently held by other local dev tooling.)

## Speaker notes

Press `S` while the deck is focused to open the speaker notes window
(separate popup, shows the current/next slide plus the notes written for
each section in `slides.md`).

## Export to PDF

1. Open `http://localhost:8422/presentation/?print-pdf`
2. Print the page (Cmd/Ctrl+P) and save as PDF. Use "Landscape" orientation
   and disable headers/footers for a clean export.

## Source

- `slides.md` is the curated source of truth for content — 17 slides
  separated by lines containing exactly `---`, with speaker notes on lines
  starting `Note:`. Edit that file, not `index.html`, to change slide
  content.
- `index.html` loads reveal.js from `node_modules/reveal.js` (npm package,
  not vendored) and renders `slides.md` via the markdown plugin.
- `css/deck.css` holds presentation-specific styling on top of reveal's
  `white` theme.
- `img/*.svg` are architecture diagrams rendered from the mermaid blocks in
  `../../architecture-diagrams.md` (i.e. `docs/architecture-diagrams.md`).
  If those mermaid blocks change, re-render the affected diagram(s) with:

  ```bash
  npx @mermaid-js/mermaid-cli -i <file>.mmd -o <file>.svg -b transparent
  ```

  and drop the resulting SVG back into `img/`.
