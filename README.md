# UI Overhaul

[mod.io page](https://mod.io/g/transportfever3/m/ui-overhaul)

A Transport Fever 3 mod that makes the game's own screens quicker to read and to act in. It adds no new windows and no notifications. The vanilla Line Manager, Statistics, entity windows and construction menu show more and need fewer clicks, so there is nothing new to learn.

It shows only what the game itself already shows somewhere: a vehicle's load in the Line Manager because the vehicle window shows it, the passengers waiting at a stop in the line window because the station window shows them. Figures the game computes but never shows are left out.

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
- The Vehicles card has *Add Vehicle*, which buys a copy of the line's newest vehicle, and *Remove Vehicle*, which sends the oldest one to a depot and sells it there. When the game refuses (not enough money, a vehicle a mission protects, no depot), the card says why under the buttons, as the vehicle window does.
- A Stops card lists every stop with everything waiting there (passengers and cargo) and a *Select Terminals* button. The tooltip splits it by passengers and cargo type, and the column sorts by it.
- A stop the line's vehicles cannot reach (no path into it, or an incompatible or doubled stop) is greyed with an alert icon. Its tooltip gives the game's own problem text, such as "Missing catenaries".

### Vehicle window

- Hovering a vehicle on the map shows, under its name, its line, next stop, speed (or why it stands), load, condition and delivery quality (passenger happiness, cargo on time).

- Vehicles with power get a Performance card with the rating the vehicle store shows for them (Poor to Excellent).

### Statistics

The Lines, Vehicles and Stations tabs get quick filters above the table and the totals of the rows shown.

| Tab | Quick filters | Totals |
|---|---|---|
| Lines | All, Losing money, Problems, No vehicles | lines, vehicles, balance |
| Vehicles | All, Losing money, Problems, Old | vehicles, balance |
| Stations | All, Problems, Crowded, No lines | stations, upkeep |

The Warehouses tab shows each cargo's icon with its quantity, the largest first, and has the quick filters All, Full and Empty with the totals (warehouses, stored of capacity, upkeep). A cargo drop-down next to the quick filters lists the warehouses that hold one cargo and sorts the Stocks column by its quantity.

Sorting is fixed where vanilla sorts by something other than what it shows: line vehicle counts, line balance, vehicle age (ascending is now youngest first) and station utilization. Vehicle ages are red once the lifespan is reached. *No lines* lists your stations that no line uses, which vanilla hides.

### Finances

- The Finances tab shows the game's figures as an income statement (revenue, running costs, operating result, interest, net income). *Details* shows the game's own table.

### Windows

- Statistics, Line Manager, Finances, Company and the notification log can stay open side by side and next to entity windows. Clicking the map no longer closes them, and *Manage Line* no longer closes the line window.
- Every window with a title bar and a close button (entity windows, Finances, Company, the vehicle store, layers, mods' windows ...) has a minimize button in its title bar, in the close button's design, with the title bar's own buttons on the right: it folds the window to its title bar, keeps its place and its content. Finances, Company and Statistics fold too, though the game gives them a fixed size. The Line Manager, which has no title bar, gets a slim title row with its name and the button; folded, only that row stays.
- Sections you open in an entity window stay open the next time, and several can be open at once.
- *Sell* in the vehicle window needs a second click.

### Industry window

- A Development card: the recipes in words ("4 Clay -> 4 Bricks, up to 460 per year"), the level while the industry can still grow, how much of its output is transported, and what keeps it from expanding (maximum reached, something in the way, nothing produced or transported, closure countdown).
- When something blocks the next expansion, an eye button in the Development card shows or hides the game's red area on the map, so you can see what stands there. (Its colour is fixed by the engine and cannot be made see-through.)
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

### Sliders

- The mouse wheel moves a construction slider (height, incline, bend ...) or a slider in the game bar one step. Over a slider in a list or window that scrolls, the wheel scrolls, as without the mod.
- A value can be typed: double-click a slider, or click the value next to a construction slider (height, incline, bend). A typed value picks the nearest one the game offers.
- The settings menu keeps its sliders as they are.

### Notifications

- Notifications of the same kind share one icon with a count, for example three "noise" warnings. Clicking it jumps to each of them in turn; right-clicking dismisses the whole group. Which notifications appear is unchanged.
- Notification icons keep the game's colours in darker shades with at least 7:1 contrast to the white symbol (WCAG AAA), also on hover: amber warnings, red problems, blue information, green achievements. The game's yellow had 1.6:1.

### Map

- Two buttons in the mod button area of the game bar keep the passenger and the cargo catchment areas of all stations on the map, each switched on and off separately. They show whenever no tool or window draws its own overlay, and the choice is saved with the game.

### Subsidies

- Subsidy icons in the notification row and their hover card show their state: available blue, in progress orange, effect active green, failed red, a missed offer grey. Every colour keeps at least 7:1 contrast to the white symbol (WCAG AAA), also on hover. Their timer ring is drawn in plain white.
- Offers have a ring and a bar for the time until the offer ends, and the card says "Time limit: 2 years - Offer ends in 3 months". Active subsidies say "Time limit" and "1 year 3 months left"; completed ones show how long their effect lasts.

### Game bar and vehicle store

- The Earnings tooltip also shows the cash flow of the last 30 days and of the 30 days before.
- The vehicle store lists the newest models first and preselects the newest one. Your sort choice is kept until you leave the game. This applies to the list layout; the table layout keeps the vanilla order.

## Settings

Every part of the mod can be switched off on its own, in the mod's settings: the gear next to UI Overhaul in the game's mod list, also when you load a savegame. A part you switch off is vanilla again, and other mods that change it work as without UI Overhaul.

| Setting | What it switches |
|---|---|
| Line Manager | line and vehicle rows, the model row, the questions before cloning or replacing several vehicles, the add-stop hint, reopening on the last line (needs Windows side by side) |
| Select Terminals | the terminal popover's buttons, highlighting and greying |
| Station window: Select Terminals | the button per line stop in the station window |
| Line window | the Vehicles card's rows and buttons, the Stops card |
| Vehicle hover on the map | the vehicle tooltip on the map |
| Vehicle performance | the Performance card |
| Statistics | the four Statistics tabs |
| Finances | the income statement in the Finances tab |
| Windows side by side | the tool windows staying open |
| Minimize button | the minimize button |
| Sections stay open | sections of entity windows staying open, several at once |
| Sell: second click | the second click on *Sell* in the vehicle window |
| Town growth | what limits growth, and the progress as text, in the town window |
| Promotion pending | the text on a perk locked by a rank already reached |
| Industry window | the Development and Served by cards, the red-area switch |
| Construction menus | the merged menus, track order, Configure, the settings above the game bar |
| Bulldozer warning | the bulldozer's warning about stations that lines stop at |
| Sliders | mouse wheel on construction and game-bar sliders, typed values |
| Notifications | the grouped notification icons and their colours |
| Catchment area buttons | the two catchment buttons |
| Subsidies | subsidy colours and texts |
| Earnings tooltip | the 30-day figures |
| Vehicle store: newest first | the store's order |

## Compatibility

- You can add the mod to a savegame and remove it again. It changes only the user interface and adds no game script.
- If one of its changes fails, that screen falls back to vanilla and the rest of the game's UI keeps working. After a game update, a part whose base screens or functions the game no longer has stays vanilla, and the game log names what is missing.
- **The mod list decides.** Where UI Overhaul and another mod change the same part of the UI, the mod that comes first in the mod list (the lower activation number, loaded first) wins; the other one's version of that part is left out, and everything else of both mods stays. Move a mod up or down in the list to choose. In detail:
  - A screen both replace (for example the Finances table): the one that comes first is shown. If that is the other mod, UI Overhaul leaves this part alone, as if it were switched off.
  - A function both extend (for example the build tooltip or the terminal popover): both changes stay, and the one that comes first has the last word. (Where mods before and after UI Overhaul extend the same function, a later one can still come last, as it would without UI Overhaul.)
  - Mods that show the same information in their own way are recognised: Industry UI Enhanced (industry window cards), Terminal Selector (station window terminal buttons), Easy Terminal Assignment (terminal popover) and Real Financial Statements (Finances table). The one that comes first is shown, the other is held back.
  - The game log (`stdout.txt`) names each decision in lines starting with `[ui_overhaul]`.
- Tested together, in both orders, with Timetables, Auto Line Namer, Auto Assign Terminals, Terminal Selector, Real Financial Statements, Track & Road Build Info, Industry UI Enhanced, Warehouse Station Coverage, Clean Vehicle View, Supply Chain Manager, Dark UI, Auto Signals, Parallel Tracks, Parallel Roads, Realistic Train Brakes and Tunnel Portal Fix.
- Screens: tested at 1024x768 (4:3), 1280x720, 1920x1080 (16:9), 2560x1080 and 3440x1440 (21:9), with small, medium and large text and a fixed UI scale of 1.5. Popovers that the game would place past the edge of the screen are moved onto it.
- The parts of the game it replaces (another mod that replaces the same one is decided by the mod list):
  - the Line Manager's vehicle list, row icons and add-stop hover;
  - the Statistics Lines, Vehicles, Stations and Warehouses tabs;
  - the line window's Vehicles card and the Finances tab's table;
  - the map's entity hover tooltip and the industry window (calling the original);
  - the game bar's Earnings display, the notification icons and the window stack.
- The entity windows' action bar is not replaced but wrapped (for *Sell*), so other mods that wrap it as well (Warehouse Station Coverage) keep working in either order.
- English, German, French, Italian, Spanish, Dutch, Japanese, Korean, Polish, Brazilian Portuguese, Russian and Chinese (simplified and traditional): all the game's languages.


## Reporting a problem

Please say in the report:

- which window or screen it is, and what you did before;
- your mod list, in its order (the order decides where two mods change the same screen);
- the lines starting with `[ui_overhaul]` from the game log. The log is `stdout.txt` in `Steam\userdata\<your Steam id>\3493540\local\crash_dump\`. It is written anew at every start, so copy it right after the problem, before you start the game again.

If a part of the mod gets in your way, switch that part off in the mod's settings (the gear next to UI Overhaul in the mod list): it is vanilla again.
## Development

The repository follows [tf3-mod-template](https://github.com/maxblan/tf3-mod-template).

```bash
make deps                          # once
make lint typecheck test           # luacheck, strict type check and offline specs
make test-ingame                   # in-game checks on a small new map
make test-ingame SAVE="My Save"    # the same on a temporary copy of a savegame
make test-ingame SAVE="My Save" WITH="celmi_timetables terminal_selector" MODS_FIRST=1
                                   # with installed mods, before this one in the mod list
make test-ingame WINDOW=1280x720 FONT=LARGE UI_SCALE=1.5 NO_SHOTS=1
                                   # another screen size, text size or UI scale; no screenshots
make validate                      # the game's mod validator
make gallery                       # the mod.io gallery cards (docs/gallery.md)
```

`_metadata/mod.io_fileid.txt` links the mod to its mod.io entry. Keep it in the repository: `make deploy` copies it to the staging area, so publishing from the game updates the existing mod instead of creating a new one.

The in-game checks take screenshots of every changed screen into `spec/ingame/results/`. [CONTRIBUTING.md](CONTRIBUTING.md) explains the rules that keep the game's UI from breaking.

| Path | Content |
|---|---|
| `src/ui_overhaul/content/ui_overhaul/gui/` | one module per change, installed by `installer.lua`; `priority.lua` decides where another mod changes the same part, `settings.lua` reads the player's switches |
| `docs/inventory/` | inventory of the game's UI, read from its source |
| `docs/improvements.md` | ranked improvement candidates, with status |
| `docs/api_cookbook.md` | engine API notes for GUI work |
| `docs/design.md` | how the mod is built and the rules it follows |
| `docs/gallery.md` | the mod.io gallery (`_metadata/1.png` …): how the cards are made, their captions |
| `types/` | type stubs for the engine API and the base-game modules the mod requires (`make typecheck`) |
| `tools/extract_game_sources.sh` | extracts the game's GUI sources to `.game/` for reference |

## License

[MIT](LICENSE). Transport Fever 3 is a trademark of Urban Games. This project is not affiliated with Urban Games or Paradox Interactive.
