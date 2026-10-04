# UI Overhaul

[mod.io page](https://mod.io/g/transportfever3/m/ui-overhaul)

A Transport Fever 3 mod that makes the game's own screens quicker to read and to act in. It adds no new windows and no notifications. The vanilla Line Manager, Statistics, entity windows and construction menu show more and need fewer clicks, so there is nothing new to learn.

## What changes

### Line Manager

- Line rows show what the line carries (cargo icons), the vehicle count and the 12-month balance, in red when the line loses money. Vehicle rows show the load, a condition icon and the age, in red once the lifespan is reached; their tooltip names the next stop, speed, load, condition and delivery quality.
- A row above the vehicle list shows each vehicle model in it with its count. Clicking a model selects exactly those vehicles; *In all lines* adds that model's vehicles from every line, so one Replace, Sell or Send to Depot reaches all of them. Shift+click on a vehicle selects all listed vehicles of its model.
- In *Select Terminals*, each terminal has three buttons (Don't Use, Alternative, Preferred) instead of a drop-down list, so a change takes one click.
- In *Select Terminals*, the preferred terminal is highlighted. Terminals the line cannot use (another kind of vehicle, a passenger terminal on a freight line and the reverse) or cannot reach (no path, with the missing piece such as catenaries) are greyed, and their tooltip says why. This also works when the popover is opened from the station or line window.

### Station window

- In the Terminals list, every line stop has a *Select Terminals* button. It opens the same terminal popover as the Line Manager, for that stop.
- Reopening the Line Manager selects the line you had selected before.
- Cloning or replacing more than one vehicle asks first, in the Line Manager's own prompt.
- With two or more lines ticked, or vehicles from several lines selected, clicking a station creates the new line without moving those vehicles onto it.
- When adding a stop, the hover says if vehicles could not get there from the stop before it, or on to the next stop.

### Line window

- Each vehicle in the Vehicles card shows its load and a condition icon, with the next stop, speed, load, condition and delivery quality in the tooltip.
- The Vehicles card has *Add Vehicle*, which buys a copy of the line's newest vehicle, and *Remove Vehicle*, which sends the oldest one to a depot and sells it there.
- A Stops card lists every stop with its waiting passengers and a *Select Terminals* button. The tooltip adds waiting cargo.
- A stop the line's vehicles cannot reach (no path into it, or an incompatible or doubled stop) is greyed with an alert icon. Its tooltip gives the game's own problem text, such as "Missing catenaries".

### Vehicle window

- Hovering a vehicle on the map shows, under its name, its line, next stop, speed (or why it stands), load, condition and delivery quality (passenger happiness, cargo on time).

- Trains and trams get a Performance card: the game's rating (Poor to Excellent) and the top speed on flat track and on medium and steep slopes, with the time and distance to reach it, fully loaded and without load. In the vehicle store's composition, the Performance row's tooltip shows the same.

### Statistics

The Lines, Vehicles and Stations tabs get quick filters above the table and the totals of the rows shown.

| Tab | Quick filters | Totals |
|---|---|---|
| Lines | All, Losing money, Problems, No vehicles | lines, vehicles, balance |
| Vehicles | All, Losing money, Problems, Old | vehicles, balance |
| Stations | All, Problems, Crowded, No lines | stations, upkeep |

The Warehouses tab shows each cargo's icon with its quantity, the largest first, and has the quick filters All, Full and Empty with the totals (warehouses, stored of capacity, upkeep). The cargo icons above the table list the warehouses that hold or take one cargo and sort the Stocks column by its quantity.

Sorting is fixed where vanilla sorts by something other than what it shows: line vehicle counts, line balance, vehicle age (ascending is now youngest first) and station utilization. Vehicle ages are red once the lifespan is reached. *No lines* lists your stations that no line uses, which vanilla hides.

### Finances

- The Finances tab shows the game's figures as an income statement (revenue, running costs, operating result, interest, net income), a cash flow statement (net income, vehicles bought and sold, construction, loans taken and repaid, change in the bank account) and a balance sheet (bank account, vehicles at their depreciated value, other assets, debt, company value). *Details* shows the game's own table.

### Windows

- Statistics, Line Manager, Finances, Company and the notification log can stay open side by side and next to entity windows. Clicking the map no longer closes them, and *Manage Line* no longer closes the line window.
- Sections you open in an entity window stay open the next time, and several can be open at once.
- *Sell* in the vehicle window needs a second click.

### Industry window

- A Development card: the recipes in words ("4 Clay -> 4 Bricks, up to 460 per year"), the level while the industry can still grow, the chance that it expands at its next half-yearly check with the production rating and how much of its output is transported, and what keeps it from expanding (maximum reached, something in the way, nothing produced or transported, closure countdown).
- A Served by card lists your lines with a stop that reaches the industry; each name opens the line.

### Towns and company

- The town window names what limits growth ("Limited by Traffic") and shows the progress to the next town level as text.
- A perk that is still locked although the game bar shows the required rank says *Promotion pending - open the Company window to unlock*.

### Construction

- The Rail and Tracks menus show each other's tabs, and so do Road and Roads. Each game-bar button still opens on its own first tab.
- Tracks are listed fastest first, and tracks you can already build come before future ones, so the preselected track is the best one available.
- *Configure* on a station opens the Tracks, Platforms, Road Access or Building tab instead of Decoration.
- The bulldozer's tooltip warns before it removes a station that lines stop at.
- The construction settings (bottom left, and the Settings window) no longer slip under the game bar or off the screen at large UI or text scales: they scroll instead.
- While you draw track or road, the build tooltip measures it: the steepest gradient and the tightest curve radius, each with the limit of the chosen type, the height range, and how far bridges run above and tunnels below the ground.

### Sliders

- The mouse wheel moves the slider under the cursor: to the next snap point, or one step while the precision key is held.
- Sliders with many steps have snap points every few percent of the range (every 5 on 0 to 100, for example), shown as ticks. A dragged slider sticks to one when it comes close; the precision key turns that off.
- A value can be typed: double-click a slider, or click the value next to a construction slider (height, incline, bend). A typed value picks the nearest one the game offers.
- The settings menu keeps its sliders as they are.

### Notifications

- Notifications of the same kind share one icon with a count, for example three "noise" warnings. Clicking it jumps to each of them in turn; right-clicking dismisses the whole group. Which notifications appear is unchanged.

### Map

- Two buttons in the mod button area of the game bar keep the passenger and the cargo catchment areas of all stations on the map, each switched on and off separately. They show whenever no tool or window draws its own overlay, and the choice is saved with the game.

### Subsidies

- Subsidy icons in the notification row show their state: offers and active subsidies keep their purple, a subsidy whose effect is active is green and a missed one grey. The timer ring is easier to read and turns amber when half the time is gone and red at the last quarter.
- Offers have a ring and a bar for the time until the offer ends, and the card says "Time limit: 2 years - Offer ends in 3 months". Active subsidies say "Time limit" and "1 year 3 months left"; completed ones show how long their effect lasts.

### Game bar and vehicle store

- The Earnings tooltip also shows the cash flow of the last 30 days and of the 30 days before.
- The vehicle store lists the newest models first and preselects the newest one. Your sort choice is kept until you leave the game. This applies to the list layout; the table layout keeps the vanilla order.

## Compatibility

- You can add the mod to a savegame and remove it again. It changes only the user interface and adds no game script.
- It uses the game's UI extension points and replaces some vanilla UI parts. If one of its changes fails, that screen falls back to vanilla and the rest of the game's UI keeps working.
- Two mods cannot replace the same vanilla part. This mod replaces the Line Manager's vehicle list, row icons and add-stop hover, the Statistics Lines, Vehicles and Stations tabs, the line window's Vehicles card, the game bar's Earnings display, the notification icons, the window stack and the entity windows' action bar. It also wraps the popover window content to swap in the terminal buttons, which works together with Auto Assign Terminals. Other mods that replace one of these will conflict. Timetables and Auto Line Namer work alongside it.
- Terminal mods:
  - [Terminal Selector](https://mod.io/g/transportfever3/m/terminal-selector) first put a terminal button into the station window. With it active, its station window and buttons are used.
  - [Easy Terminal Assignment](https://mod.io/g/transportfever3/m/easy-terminal-assignment) has its own one-click design for the terminal popover. With it active, all terminal popovers are its, including the ones this mod's buttons open.
- English, German, French, Italian, Spanish, Dutch, Japanese, Korean, Polish, Brazilian Portuguese, Russian and Chinese (simplified and traditional): all the game's languages.

## Development

The repository follows [tf3-mod-template](https://github.com/maxblan/tf3-mod-template).

```bash
make deps                          # once
make lint test                     # luacheck and offline specs
make test-ingame                   # in-game checks on a small new map
make test-ingame SAVE="My Save"    # the same on a temporary copy of a savegame
make validate                      # the game's mod validator
```

`_metadata/mod.io_fileid.txt` links the mod to its mod.io entry. Keep it in the repository: `make deploy` copies it to the staging area, so publishing from the game updates the existing mod instead of creating a new one.

The in-game checks take screenshots of every changed screen into `spec/ingame/results/`. [CONTRIBUTING.md](CONTRIBUTING.md) explains the rules that keep the game's UI from breaking.

| Path | Content |
|---|---|
| `src/ui_overhaul/content/ui_overhaul/gui/` | one module per change; each is installed through a small guarded stub (`*.script.lua`, `guard.lua`) |
| `docs/inventory/` | inventory of the game's UI, read from its source |
| `docs/improvements.md` | ranked improvement candidates, with status |
| `docs/api_cookbook.md` | engine API notes for GUI work |
| `docs/design.md` | how the mod is built and the rules it follows |
| `tools/extract_game_sources.sh` | extracts the game's GUI sources to `.game/` for reference |

## License

[MIT](LICENSE). Transport Fever 3 is a trademark of Urban Games. This project is not affiliated with Urban Games or Paradox Interactive.
