# Videos

Placeholder folder for the showcase video series.

The showcase page expects these file names. Drop the recordings here and each playlist
entry starts playing — no code change required.

| Expected file | Video |
|---|---|
| `01-solution-overview.mp4` | Solution overview |
| `02-private-networking.mp4` | Private networking walkthrough |
| `03-apim-databricks.mp4` | API Management and Databricks |
| `04-custom-connector.mp4` | The custom connector |
| `05-copilot-studio-agent.mp4` | Building the Copilot Studio agent |
| `06-deck-generation.mp4` | Generating the deck |

Until a file exists the player shows a "not published yet" notice naming the missing file.

To change the list, edit the `videos` array in
[../../ui/src/app/showcase/showcase.page.ts](../../ui/src/app/showcase/showcase.page.ts).

Videos are served through Git LFS media URLs, so commit them with LFS tracking enabled:

```bash
git lfs track "docs/Videos/*.mp4"
```
