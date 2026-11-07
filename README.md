# Smart Divider

A theme-aware divider for the Omarchy bar — built to carve the bar into
sections. Right-click one to pick its shape, size and colour, or add another;
then drag each one wherever you want it.

![Divider preview](preview.png)

## Why

The stock bar lays chips out in one long run. A divider makes the groups
readable: system, network, media, power, and so on. This plugin makes dividers
cheap to create and easy to rearrange, without adding a new plugin id for every
line. Unlike a divider that you add repeatedly from settings, right-clicking
the one in front of you duplicates it in place.

## Features

- **Five shapes.** Line (the default thin rule), dot, oval, square, and
  rounded square. Each divider keeps its own, so a bar can mix a rule between
  app groups with dots around the clock.
- **Any size.** Width and height are set separately as a percentage of the bar
  height, so a mark keeps its proportions when the bar changes. 8% × 62% is the
  original rule.
- **Theme colours or your own.** Theme, accent, bar foreground, urgent, or any
  `#rrggbb` typed into the menu.
- **Right-click for the style menu.** Shape previews, width and height sliders,
  the colour row, and a Duplicate action in one popover. The bar previews every
  change live; the style is saved when the menu closes.
- **Duplicate in place.** A new divider appears immediately after the one you
  clicked, carrying the shape, size and colour on screen.
- **Independent placement.** Every divider is its own bar layout entry, so the
  bar's normal left-drag moves each one separately.
- **Drag off to remove.** Pull a divider off the bar and it disappears.
- **Remembers its place and its style.** Each copy gets a stable `dividerId`
  and its own `shape`, `width`, `height` and `color` in its layout entry, so
  duplicating always puts the new mark beside the one you clicked, looking the
  same.

## Requirements

- Omarchy 4 (Quattro) with `omarchy-shell`
- `bash`
- `jq`
- `flock` (util-linux)

No network access, background polling, or external services.

## Installation

Install from the marketplace, or directly from this repository:

```bash
omarchy plugin add https://github.com/nikhill-666/omarchy-smart-divider.git --enable
```

Then add a divider from the bar settings, or place one yourself:

```bash
omarchy plugin enable io.github.nikhill-666.divider --after omarchy.workspaces
```

Once one divider is on the bar, right-click it to change its style or add as
many more as you need.

## Usage

| Action | Result |
| --- | --- |
| Right-click a divider | Opens the style menu |
| Pick a shape, size or colour | Changes this divider only |
| “Duplicate divider” | Adds a copy directly after it, with the same style |
| Left-drag a divider | Moves it anywhere on the bar |
| Drag a divider off the bar | Removes it |

The divider is intentionally not a button: a plain left-click does nothing, so
it never steals the drag gesture from the bar. Nothing is written to disk while
the menu is open — the mark updates live from the menu, and the whole style is
saved once when the menu closes, which keeps it to one config write instead of
one per slider step.

### Shapes

| Shape | Looks like |
| --- | --- |
| `line` | A thin vertical rule — the original divider |
| `dot` | A small filled circle |
| `oval` | A vertical ellipse, wider than the rule |
| `square` | A small hard-cornered square |
| `rounded` | A small square with softened corners |

Picking a shape resets width and height to that shape's natural size, unless
you have already tuned them — then your size is kept and the shape only changes
the corners. On a vertical bar the same marks are drawn on their side.

### Size

Width and height are percentages of the bar height: width 2–30, height 6–100.
Both are per divider. A shape's starting size is:

| Shape | Width | Height |
| --- | --- | --- |
| `line` | 8% | 62% |
| `dot` | 22% | 22% |
| `oval` | 22% | 50% |
| `square` | 22% | 22% |
| `rounded` | 22% | 22% |

Because the units are relative, the mark grows with the bar rather than
staying a fixed pixel size.

### Colour

| Value | Colour |
| --- | --- |
| `theme` | The theme's muted tone (the original divider) |
| `accent` | The theme accent |
| `foreground` | The bar's foreground, which flips for light wallpapers |
| `urgent` | The theme's urgent/attention tone |
| `#rrggbb` | Any colour; `#abc` is expanded too |

Role colours follow the theme, so changing theme recolours every divider that
uses one. A hex colour stays as typed. The mark keeps its calm 55% opacity at
rest and brightens to 90% on hover, whatever colour it is.

## How it works

A divider is an ordinary `bar-widget` layout entry:

```json
{
  "id": "io.github.nikhill-666.divider",
  "dividerId": "divider-…",
  "shape": "dot",
  "width": 22,
  "height": 22,
  "color": "accent"
}
```

`omarchy bar put` deliberately refuses to add a second copy of a widget, and a
bar-widget plugin cannot write `bar.layout` through the shell API. So
`duplicate-divider.sh`:

1. Finds the clicked entry by its `dividerId` (and gives every older, untagged
   divider a stable id on the first duplicate).
2. Merges in the style the menu is showing, if one is passed.
3. Clones that entry immediately after itself, preserving any custom settings —
   style included.
4. Writes `~/.config/omarchy/shell.json` atomically with `jq`, then asks
   `omarchy-shell` to reload the config.

Saving a style goes through `set-divider-style.sh`, which finds the same entry
and merges only the keys it was given. It exists instead of the shell's own
`updateEntryInline` because that helper rewrites *every* entry of a widget with
`allowMultiple`: using it would give all dividers one style and one
`dividerId`. The script clamps width and height into range and rejects anything
outside the five shapes, four colour roles and `#rrggbb`. The two scripts share
a lock, so a style change and a duplicate cannot lose each other's write.

The plugin edits only `~/.config/omarchy/shell.json`. It does not overwrite any
other user configuration, and it makes no network requests.

## Removal

Remove any extra dividers first (drag them off the bar), then remove the plugin:

```bash
omarchy plugin remove io.github.nikhill-666.divider
```

If layout entries remain after removal, delete them from
`~/.config/omarchy/shell.json` and run `omarchy-shell shell reloadConfig`.

## License

MIT — see [LICENSE](LICENSE).
