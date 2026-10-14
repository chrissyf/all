// Exports each scenario of aws-architekturdiagramme.html as its own A4 PDF.
//
// Usage (from the repository root):
//   npm install --no-save playwright && npx playwright install chromium
//   node docs/export-pdf.js [output-dir]
//
// Output goes to docs/pdf/ unless another directory is given. The PDFs are
// generated files and stay out of git (see .gitignore).

const fs = require("fs");
const os = require("os");
const path = require("path");

function loadPlaywright() {
  try {
    return require("playwright");
  } catch {
    // Fall back to a globally installed copy.
    const { execSync } = require("child_process");
    const root = execSync("npm root -g", { encoding: "utf8" }).trim();
    return require(path.join(root, "playwright"));
  }
}

const SOURCE = path.join(__dirname, "aws-architekturdiagramme.html");
const OUT_DIR = path.resolve(process.argv[2] || path.join(__dirname, "pdf"));

const JOBS = [
  {
    keep: "bestellung",
    drop: "remediation",
    title: "Lösung Szenario 2: Bestellprozess",
    file: "Loesung-Szenario-2-Bestellprozess.pdf",
  },
  {
    keep: "remediation",
    drop: "bestellung",
    title: "Lösung Szenario 3: Produktions-Remediation",
    file: "Loesung-Szenario-3-Remediation.pdf",
  },
];

// The page is written as an artifact body without a document skeleton,
// so wrap it before loading it into the browser.
function wrapPage() {
  const body = fs.readFileSync(SOURCE, "utf8");
  const html =
    '<!doctype html><html lang="de"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width"></head><body>' +
    body +
    "</body></html>";
  const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "aws-diagrams-")), "page.html");
  fs.writeFileSync(tmp, html);
  return tmp;
}

async function main() {
  const { chromium } = loadPlaywright();
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const page = wrapPage();
  const browser = await chromium.launch();
  try {
    for (const job of JOBS) {
      const tab = await browser.newPage({ viewport: { width: 1240, height: 900 }, colorScheme: "light" });
      await tab.goto("file://" + page, { waitUntil: "networkidle" });
      await tab.evaluate(async (j) => {
        document.getElementById(j.drop).remove();
        document.querySelector("h1").textContent = j.title;
        document.querySelector(".lede").remove();
        document.querySelectorAll(".scroll-hint").forEach((e) => e.remove());
        document.title = j.title;
        const style = document.createElement("style");
        style.textContent = `
          :root { --bg: #fff; }
          body { padding-block: 0 !important; }
          .wrap { gap: 28px !important; }
          .figure { border-color: #e3e7ec; }
          .figure, tr, .cols > *, .scen-head, .legend { break-inside: avoid; }
          .figure svg.dg { min-width: 0 !important; }`;
        document.head.appendChild(style);
        await document.fonts.ready;
      }, job);
      const out = path.join(OUT_DIR, job.file);
      await tab.pdf({
        path: out,
        format: "A4",
        printBackground: true,
        scale: 0.6,
        margin: { top: "10mm", bottom: "12mm", left: "10mm", right: "10mm" },
        displayHeaderFooter: true,
        headerTemplate: "<span></span>",
        footerTemplate:
          '<div style="font:8px Arial;width:100%;text-align:right;padding-right:10mm;color:#666">' +
          job.title +
          ' · Seite <span class="pageNumber"></span>/<span class="totalPages"></span></div>',
      });
      await tab.close();
      console.log("wrote " + path.relative(process.cwd(), out));
    }
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
