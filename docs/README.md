docs
====

Architecture diagrams for the AWS exercise "Architekturdiagramme zeichnen"
(German), scenarios 2 and 3.

| File                            | Content                                                                    |
| ------------------------------- | -------------------------------------------------------------------------- |
| `aws-architekturdiagramme.html` | Both solutions on one page: diagrams, step tables, error paths and limits |
| `export-pdf.js`                 | Renders each scenario into its own A4 PDF                                  |

The HTML file is an artifact body without `<html>`/`<head>`/`<body>`; browsers
render it as is, and the export script wraps it before printing.

## Exporting the PDFs

From the repository root:

```sh
npm install --no-save playwright
npx playwright install chromium
node docs/export-pdf.js
```

This writes two files to `docs/pdf/`:

- `Loesung-Szenario-2-Bestellprozess.pdf`
- `Loesung-Szenario-3-Remediation.pdf`

Pass a directory to write them elsewhere: `node docs/export-pdf.js out/`.
The page loads its fonts from Google Fonts, so the export needs network
access; without it the PDFs fall back to system fonts.

`docs/pdf/` is gitignored. Regenerate the PDFs after changing the HTML instead
of committing them.
