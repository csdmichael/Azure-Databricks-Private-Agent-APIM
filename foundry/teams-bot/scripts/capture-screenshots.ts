import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";

const output = resolve(process.cwd(), "..", "docs", "screenshots");
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: false });
const context = await browser.newContext({
  storageState: process.env.PLAYWRIGHT_STORAGE_STATE,
  viewport: { width: 1600, height: 1000 },
});
const page = await context.newPage();

const pages = [
  {
    name: "01-foundry-agent.png",
    url: process.env.FOUNDRY_AGENT_PORTAL_URL,
    ready: /semiconductor-sales-genie/i,
  },
  {
    name: "02-bot-service.png",
    url: process.env.AZURE_BOT_PORTAL_URL,
    ready: /caldova-foundry-databricks-bot/i,
  },
  {
    name: "03-bot-web-chat.png",
    url: process.env.AZURE_BOT_WEB_CHAT_URL,
    ready: /Test in Web Chat/i,
  },
];

for (const target of pages) {
  if (!target.url) {
    throw new Error(`Missing URL for ${target.name}`);
  }
  await page.goto(target.url, { waitUntil: "domcontentloaded" });
  await page.getByText(target.ready).first().waitFor({ timeout: 120_000 });
  await page.screenshot({ path: resolve(output, target.name), fullPage: true });

  if (target.name === "01-foundry-agent.png") {
    await page.getByRole("tab", { name: "YAML" }).click();
    await page.getByText("project_connection_id:", { exact: false }).waitFor({
      timeout: 120_000,
    });
    await page.screenshot({
      path: resolve(output, "05-foundry-agent-yaml.png"),
      fullPage: true,
    });

    await page.getByRole("tab", { name: "Details" }).click();
    await page.getByText("Agent configuration", { exact: true }).waitFor({
      timeout: 120_000,
    });
    await page.screenshot({
      path: resolve(output, "06-foundry-agent-details.png"),
      fullPage: true,
    });
  }
}

await context.storageState({ path: resolve(output, ".auth-state.json") });
await browser.close();
