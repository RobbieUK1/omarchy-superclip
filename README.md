# SuperClip

Enhanced clipboard manager for the Omarchy shell bar.

SuperClip is a `bar-widget` plugin: one paperclip button in the bar opens a
popup with four tabs I've tried to make it feature rich but simple:

| Tab        | What it shows                                                     |
|------------|-------------------------------------------------------------------|
| Text       | Searchable clipboard text history. Hover a row for preview tools;  |
|            | star it (paperclip) to save as a SuperClip, or delete it (Trashcan).|
|            | Click the star again to un-star.                                  |
| Images     | Clipboard image history.    |
|            | Hover a thumbnail for a large preview; save or delete individually.|
| Screenshots| The current `screenshot-*.png` files on disk. Same preview/save/   |
|            | delete actions as images.                                          |
| SuperClips | Your saved SuperClips (snippets) (text and images), searchable, with edit and   |
|            | delete actions. Add new ones with the **+ Add** button.            |

New SuperClips are added to the top of the list. Each list scrolls and stays
inside the panel's 560px height limit, with a thin scroll indicator when it
overflows.

Hovering any image (Images, Screenshots, or an image SuperClip) shows a large
preview floating beside the panel, aligned with the thumbnail. If the panel is
pinned to the left edge, the preview flips to the right side instead.

## Requirements

- Omarchy shell
- The first-party `omarchy.clipboard` plugin (writes the clipboard history
  that SuperClip reads).

## Install

```sh
omarchy plugin add https://github.com/RobbieUK1/omarchy-superclip.git --enable
omarchy restart shell
```

Right-click your bar -> **Configure bar** (or edit `~/.config/omarchy/shell.json`)
and add the widget to a section:

```json
"right": [
  { "id": "robbie.superclip" }
]
```

## How it works

- Text/images come from the shared clipboard history written by
  `omarchy.clipboard` at `~/.local/state/omarchy/clipboard-history.json`.
- Screenshots are found in your screenshot directory (`~/Pictures` by
  default) matching `screenshot-*.png`.
- SuperClips are stored in `~/.config/omarchy/canned-responses.json`.
- Pasting inserts text (or copies an image back to the clipboard) and then
  sends the terminal/focus-aware paste key to the active window.

## License

MIT
