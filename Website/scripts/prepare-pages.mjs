import { cp, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";

const clientDirectory = join("dist", "client");
const prefixedAssets = join(clientDirectory, "Filmify", "_next");
const publishedAssets = join(clientDirectory, "_next");

await rm(publishedAssets, { force: true, recursive: true });
await mkdir(publishedAssets, { recursive: true });
await cp(prefixedAssets, publishedAssets, { recursive: true });
await rm(join(clientDirectory, "Filmify"), { force: true, recursive: true });
