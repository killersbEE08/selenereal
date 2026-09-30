// Copies the shared tarot/spread/reader datasets from the Flutter assets into the functions bundle.
import { mkdirSync, copyFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const src = join(root, "..", "assets", "json");
const dst = join(root, "src", "data");
mkdirSync(dst, { recursive: true });
for (const f of ["cards.json", "spreads.json", "readers.json"]) copyFileSync(join(src, f), join(dst, f));
console.log("data copied");
