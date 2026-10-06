# Foundry showcase videos

The Foundry video playlist is generated from the `.mp4` files in this folder.
Running `npm --prefix ui run build` regenerates
`ui/src/app/showcase/foundry-videos.generated.ts` before compiling the app.

To publish another episode:

1. Add the `.mp4` file to this folder.
2. Optionally add its title, description, and duration to `videos.json`. Files
   without metadata use their file name as the title.
3. Run the UI build and commit the recording, metadata, and generated TypeScript.

Videos are ordered by file name unless their metadata contains a numeric `order`
value. Angular copies the recordings directly from this folder to
`assets/foundry/videos` during the build, so no duplicate source files or runtime
directory API are needed.
