import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import AdmZip from "adm-zip";

const botRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const repoRoot = resolve(botRoot, "..", "..");
const config = JSON.parse(
  await readFile(resolve(repoRoot, "config", "deployment.json"), "utf8"),
) as {
  teams: { appId: string; appServiceName: string; packageName: string };
};
const teamsAppId = process.env.TEAMS_APP_ID ?? config.teams.appId;
const botId = process.env.BOT_ID ?? config.teams.appId;
const botHostName =
  process.env.BOT_HOST_NAME ?? `${config.teams.appServiceName}.azurewebsites.net`;
const template = await readFile(
  resolve(botRoot, "appPackage", "manifest.template.json"),
  "utf8",
);
const manifest = template
  .replaceAll("{{TEAMS_APP_ID}}", teamsAppId)
  .replaceAll("{{BOT_ID}}", botId)
  .replaceAll("{{BOT_HOST_NAME}}", botHostName);
JSON.parse(manifest);

const outputDir = resolve(repoRoot, "foundry", "Teams Package");
await mkdir(outputDir, { recursive: true });
const zip = new AdmZip();
zip.addFile("manifest.json", Buffer.from(manifest));
zip.addLocalFile(resolve(botRoot, "appPackage", "color.png"));
zip.addLocalFile(resolve(botRoot, "appPackage", "outline.png"));
const target = resolve(outputDir, config.teams.packageName);
zip.writeZip(target);
await writeFile(resolve(outputDir, "manifest.json"), manifest);
console.log(`Teams package: ${target}`);
