# mod.io gallery

Fourteen 1920 x 1080 cards, each a small feature story: the screen, a headline that names what the player
gains, one line of explanation, and the screenshots. They share the thumbnail's look
(`assets/preview.svg`): its dark blue glow, screenshots in a silver bevelled rim like its window, round
silver markers like its close button, and white frames with a soft glow for where to look. The
order follows the strongest visible change first: three before/after cards, the spotlights, a
workflow, the overview.

## Making them

1. Take the screenshots (Transport Fever 3 closed, Steam running). Both runs load a copy of the
   savegame with only the game's own content and this mod (the second without it), pause it, switch
   the game to English and large text for the run and put your settings back afterwards:

   ```bash
   spec/ingame/run.sh --save "World#1" --gallery --language en
   spec/ingame/run.sh --save "World#1" --gallery --language en --vanilla
   ```

   The scenes are the `gallery_*` entries in `gui_checks.lua`; the shots land in
   `spec/ingame/results/gallery-mod/` and `gallery-vanilla/`. Leave mouse and keyboard alone while
   it runs: for the hover tooltips and the track tool, `run.sh` moves the mouse and clicks where the
   testbench asks. The subsidy scene adds offers with the game's own debug event, in the savegame copy
   only (it is deleted afterwards). `--only gallery_<name>` takes single scenes again.
2. `make gallery` composes the cards (`tools/gallery/compose.py`, crops in screenshot pixels) and
   renders them with the game's font, Lato, to `assets/gallery/01-…png` … `14-…png` (kept in the
   repository).

The frames are measured on the shots of `World#1` (screenshot pixels, 3440 x 1440). Another savegame
or screen size shows other lines and places: measure the regions in `compose.py` again on its shots.

## Page text

Upload the cards in this order; the captions are for the gallery, the longer text for the mod page.

| # | Card | Caption |
|---|------|---------|
| 1 | `01-line-manager-before-after` | See which lines lose money at a glance |
| 2 | `02-line-window-before-after` | Add or remove a vehicle without the Line Manager |
| 3 | `03-vehicle-hover-before-after` | Hover a vehicle, see how it is doing |
| 4 | `04-terminals` | Set a stop's terminals in one click |
| 5 | `05-industry` | Know why an industry isn't growing |
| 6 | `06-statistics` | Find the lines that lose money in one click |
| 7 | `07-warehouses` | See what lies in every warehouse |
| 8 | `08-finances` | Read your company like a balance sheet |
| 9 | `09-build-tooltip` | Know the gradient before you build |
| 10 | `10-notifications` | Fewer icons, clearer colours, offers that say when they end |
| 11 | `11-catchment` | Keep every station's catchment area on the map |
| 12 | `12-minimize` | Minimize any window to its title bar |
| 13 | `13-workflow-replace-model` | Replace a bus model across your whole network |
| 14 | `14-overview` | More to read, fewer clicks, in the windows you know |

1. **Line Manager.** Every line shows its vehicle count and its balance over the last 12 months, red
   when it loses money, and every vehicle its load, condition and age. The same window, same scene:
   left without the mod, right with it.
2. **Line window.** Each vehicle shows its load and condition. *Add Vehicle* buys a copy of the line's
   newest vehicle, *Remove Vehicle* sends the oldest to a depot and sells it. A Stops card lists every
   stop with who waits there and a terminal button.
3. **Vehicles on the map.** Hovering a vehicle shows its line, next stop, speed (or why it stands),
   load, condition and passenger happiness or cargo on time.
4. **Stations.** The station window's terminal list has a button next to every line that stops
   there. It opens the line's terminals for that stop: Preferred, Alternative or Don't use, one click
   each, without opening the Line Manager. A line that cannot reach the stop gets a warning sign, and
   the button's tooltip says why.
5. **Industries.** The Development card shows the level, how much of the output is transported, the
   chance of the next expansion and what keeps the industry from growing; the eye button shows or
   hides the red area of a blocked expansion. Served by lists the lines that reach it.
6. **Statistics.** Quick filters above the Lines, Vehicles, Stations and Warehouses tabs (losing
   money, problems, no vehicles, old, crowded …), and totals for exactly what the filter shows.
7. **Warehouses.** Each warehouse lists its cargo with the amounts, largest first. Full and Empty
   filter the list, a cargo picker shows only the warehouses holding that cargo, and the totals add
   up what is shown.
8. **Finances.** The Finances tab shows the game's figures as an income statement, a cash flow
   statement and a balance sheet; *Details* keeps the game's own table.
9. **Construction.** While you draw track or road, the build tooltip gives the length, the steepest
   gradient and the tightest curve with the limits of the chosen type, the height range and the angle.
10. **Notifications.** Notifications of the same kind share one icon with a count; click to visit
    each, right-click to dismiss the group. Every icon colour, subsidies included, has at least 7:1
    contrast to its white symbol, and subsidy offers say when they end.
11. **Map.** Two buttons keep the passenger and the cargo catchment areas of all stations on the map,
    each on its own. The choice is saved with the game.
12. **Windows.** Every window with a close button gets a minimize button next to it. A minimized
    window folds to its title bar and keeps its place, tabs and scroll position.
13. **Replacing a model.** Select the model in the row above the vehicle list, add its vehicles from
    every line with "In all lines", then replace them in one go. The Line Manager asks before it
    replaces or clones several vehicles.
14. **Overview.** The windows you already use, side by side: the Line Manager with balances and the
    model row, Statistics, and a vehicle window with its performance on slopes. Notifications of one
    kind share an icon, and every window can be minimized to its title bar.
