# Videos

Placeholder folder for the showcase video series.

The showcase page expects these file names. Drop the recordings here and each playlist
entry starts playing — no code change required.

| Expected file | Video | Status |
|---|---|---|
| `01-solution-overview.mp4` | Solution overview | Published (11:32) |
| `02-private-networking.mp4` | Private networking walkthrough | Published (5:45) |
| `03-apim-databricks.mp4` | API Management and Databricks | Not recorded |
| `04-custom-connector.mp4` | The custom connector | Not recorded |
| `05-copilot-studio-agent.mp4` | Building the Copilot Studio agent | Not recorded |
| `06-deck-generation.mp4` | Generating the deck | Not recorded |

Until a file exists the player shows a "not published yet" notice naming the missing file.

To change the list, edit the `videos` array in
[../../ui/src/app/showcase/showcase.page.ts](../../ui/src/app/showcase/showcase.page.ts).

`*.mp4` in this folder is already tracked by Git LFS via the repository `.gitattributes`,
so committing a new recording needs no extra setup — just remember to update the matching
`duration` field so the playlist shows the running time instead of "Coming soon".
