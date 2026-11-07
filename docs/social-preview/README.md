# Social preview kit

Builds `docs/social-preview.jpg` (1280×640 JPEG, under 1 MB), the card GitHub, X, Slack and WeChat show for
the repository link.

- `background.jpg` — abstract oil painting from an image model, prompt:
  > "Abstract expressive oil painting filling the whole frame, wide 16:9: thick visible brushstrokes, canvas
  > texture, soft painterly blending, diagonal sweeping strokes, editorial OpenAI-blog-cover aesthetic.
  > ABSOLUTELY NO text, letters, logos, symbols, faces or objects. Keep the center calmer and mid-tone so white
  > text stays readable. Palette: deep plum and warm amber, like late-night radio and sound drifting through a
  > room, with accents of coral, pink, turquoise and golden yellow."
- `icon.svg` — Lucide `audio-lines` icon (ISC license).
- `render.py` — lays the white icon and wordmark over the background with headless Google Chrome, keeping the
  lockup inside the central square so chat apps' square crops keep it whole.

Rebuild from the repository root:

```sh
python3 docs/social-preview/render.py --background docs/social-preview/background.jpg \
  --icon docs/social-preview/icon.svg --name "Earshot|iPhone audio recorder" \
  --tagline "Any app's sound or the room · transcripts on your Mac" --out docs/social-preview.jpg
```

Upload it in the repository's Settings → General → Social preview.
