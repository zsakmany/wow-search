# Opening Blizzard windows through a secure button (issue #39)

Status: **draft**. The facts below come from Blizzard's code. The "Results" sections are empty until the owner tests in the game.

Related bugs: #27 (bags), #29 (spellbook), #38 (world map). Use actions and the Enter binding: #22.

## The question

Seek opens Blizzard windows by calling Blizzard's functions from its own code (`OpenBag`, `PlayerSpellsUtil.OpenToSpellBookTabAtSpell`, `QuestMapFrame_OpenToQuestDetails`, `OpenWorldMap`). Blizzard's code then runs as Seek's code. What it writes is tainted, and later protected actions are blocked.

Can a secure path run Blizzard's own code instead, started by the player's Enter? And how far can that path steer each window?

## Short answer (expected, not yet tested)

| Window | Secure open | Steer to the right place | Confidence |
|---|---|---|---|
| Bags | Yes: click a bag slot button, or a bag binding | Yes: one `/click` per closed bag that holds the item | High for open, medium for "no taint" |
| Spellbook | Yes: click `SpellbookMicroButton`, or `TOGGLESPELLBOOK` | Partly: click the category tab, then "next page" N times. No "go to spell". | High for open, low for tab and page |
| Quest log | Yes: click `QuestLogMicroButton`, or `TOGGLEQUESTLOG` | Yes, probably: then click the quest's title button in the log. That shows the details **and** moves the map to the quest's zone with a ping. | Medium |
| World map alone | Yes: `TOGGLEWORLDMAP` binding only (no micro button) | No: the map opens at the player's zone | High |

In combat, nothing can be prepared: attributes and bindings are locked. Seek clears its Enter binding when combat starts. So in combat the secure path is not available from the search bar.

## Facts from Blizzard's code

Source: [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), branch `forever` (the Forever client). Paths below are under `Interface/AddOns/`. Wiki: [warcraft.wiki.gg](https://warcraft.wiki.gg).

### General

1. **Secure action button, type `click`.** It calls `clickbutton:Click(button)`. It refuses a button that has access constraints or that forbids scripted input. `clickbutton` is a frame, so it can be an unnamed button. Source: `Blizzard_FrameXML/SecureTemplates.lua`, `SECURE_ACTIONS.click` (line 557).
2. **Secure action button, type `macro`.** It runs `macro` (a saved macro) or `macrotext` with `C_Macro.RunMacroText`. Source: `SecureTemplates.lua`, `SECURE_ACTIONS.macro` (line 450). Limit: 255 characters ([wiki: SecureActionButtonTemplate](https://warcraft.wiki.gg/wiki/SecureActionButtonTemplate)).
3. **`/click Name [mouseButton] [down]`** is a secure slash command. It needs a global frame name. It refuses the same buttons as type `click`. It sends an up click unless `down` is given. Source: `Blizzard_ChatFrameBase/Shared/SlashCommands.lua` line 726. Since 11.0.2, a macro may not `/click` a button that runs another macro ([wiki: /click](https://warcraft.wiki.gg/wiki/MACRO_click)). A type `click` button is fine.
4. **A secure button cannot run a key binding command.** No secure type does that, and there is no slash command for it. But an **override binding can bind Enter straight to a Blizzard binding command**, such as `TOGGLEWORLDMAP`: `SetOverrideBinding(owner, true, "ENTER", "TOGGLEWORLDMAP")` ([wiki: SetOverrideBinding](https://warcraft.wiki.gg/wiki/API_SetOverrideBinding)). The command's code comes from Blizzard's `Bindings_Camelot.xml`, so it should run untainted. This gives one command per key press; it cannot chain.
5. **Combat.** `SetOverrideBinding`, `SetOverrideBindingClick`, `ClearOverrideBindings`, and `SetAttribute` on a secure button cannot be called in combat. A secure button that was prepared before combat still works in combat, when the player clicks it or presses a key bound to it.
6. **Steering with a `PreClick`.** Out of combat, a button's `PreClick` (addon code) may set the button's attributes just before its secure click. This is a common addon pattern. Whether the following secure `OnClick` stays untainted is what the prototype checks (see `/sop log quest`).

### Bags

1. **Buttons.** Backpack: `MainMenuBarBackpackButton`. Bags 1 to 4: `CharacterBag0Slot` to `CharacterBag3Slot`. Reagent bag (5): `CharacterReagentBag0Slot`. Source: `Blizzard_MainMenuBarBagButtons/Mainline/MainMenuBarBagButtonTemplates.xml` lines 43 to 122, `Camelot/MainMenuBarBagButtons.xml` line 67.
2. **What a click does.** `BagSlotOnClick`: with no modifier, it first tries `PutItemInBag` (only does something when the cursor holds an item), else `ToggleBag(bagID)`. Source: `Blizzard_MainMenuBarBagButtons/Shared/MainMenuBarBagButtons.lua` line 69. So a secure click opens exactly one bag.
3. **Bindings.** `TOGGLEBACKPACK` = `ToggleBackpack()`. `TOGGLEBAG1` = `ToggleBag(4)`, `TOGGLEBAG2` = 3, `TOGGLEBAG3` = 2, `TOGGLEBAG4` = 1. `TOGGLEREAGENTBAG1` = `ToggleBag(5)`. `OPENALLBAGS` = `ToggleAllBags()`. Source: `Blizzard_FrameXML/Bindings_Camelot.xml` lines 1176 to 1196.
4. **They toggle.** `ToggleBag` closes an open bag. Clicking the backpack while it is open closes **all** bags (`ToggleBackpack_Individual`). Source: `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua` lines 165 and 222. So Seek must click only the bags that are closed (`IsBagOpen`, line 353), decided when it prepares.
5. **Combined bags.** With "combined bags" on, `ToggleBag` of any held bag toggles the one combined window (`ToggleBag_Combined`, line 217). So with combined bags, click only one held bag. The reagent bag may stay separate (`IsUsingCombinedBags(bagID)`, line 2389).
6. **Only the right bags.** Yes in principle: a `macro` with one `/click` line per closed bag that holds the item.
7. **Seek's glow.** The glow is Seek's own texture on Blizzard's item button. Seek writes no field into Blizzard's tables. It should still work after a secure open; the prototype checks it.
8. **Combat.** The player can open bags in combat, so a prepared secure click works in combat. Seek cannot prepare one in combat.

### Spellbook

1. **Button.** Forever shows separate `SpellbookMicroButton` and `TalentMicroButton` (`Blizzard_MicroMenu/Camelot/MicroMenuContainerOverrides.lua` line 6). `SpellbookMicroButton` calls `PlayerSpellsUtil.TogglePlayerSpellsFrame(SpellBook)`. Source: `Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.xml` line 147 and `.lua` line 923.
2. **Bindings.** `TOGGLESPELLBOOK` = `PlayerSpellsUtil.ToggleSpellBookFrame()` (`Bindings_Camelot.xml` line 1211; `Blizzard_FrameXMLUtil/Mainline/PlayerSpellsUtil.lua` line 82). `TOGGLEPETBOOK` = the same at the pet category (line 1220). That is the only category a binding can choose. Both toggle: a press while the spellbook is shown closes it.
3. **No "go to spell" on a secure path.** Only `GoToSpell` finds a spell's tab and page (`Blizzard_PlayerSpells/SpellBook/Blizzard_SpellBookFrame.lua` line 376). The micro button calls it only for its own tutorial alerts (`self.jumpToSpellID`, set by Blizzard). If Seek wrote that field, the click would read a tainted value; that is the bug again.
4. **Tabs and pages by clicks.** Each spellbook category is a tab button (`CategoryTabSystem:GetTabButton(tabID)`, made in `Camelot/SpellBook/Blizzard_SpellBookFrame.lua` line 45). Its `OnClick` calls `SetTab` (`Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.lua` line 154). The page buttons are `PagedSpellsFrame.PagingControls.PrevPageButton` / `NextPageButton`; their `OnClick` is `PreviousPage` / `NextPage` (`Blizzard_PagedContent/Blizzard_PagingControls.lua` lines 20 and 21). These are Blizzard code. So a macro of secure clicks (open, tab, next page N times) might turn to the spell's page untainted. The buttons are unnamed, so each needs a named proxy button of type `click`.
5. **What Seek must still compute.** The tab and page of a spell, from addon code, by reading only. The page depends on the window size (minimized or not) and the "hide passives" setting. This is fragile.
6. **The spellbook is load-on-demand** (`PlayerSpellsFrame_LoadUI`). Its tab buttons do not exist until it has been loaded once.
7. **Combat.** The player can open the spellbook in combat. A prepared secure click works in combat. Seek cannot prepare one in combat.

### Quest log and world map

1. **No world map micro button** in Forever. `QuestLogMicroButton` calls `ToggleQuestLog()` (`MainMenuBarMicroButtons.lua` line 1119), which opens the world map with the quest log panel (`Blizzard_WorldMap/QuestLogOwnerMixin.lua` line 54).
2. **Bindings.** `TOGGLEQUESTLOG` = `ToggleQuestLog()`. `TOGGLEWORLDMAP` = `ToggleWorldMap()`. Source: `Bindings_Camelot.xml` lines 1229 and 1232; `Blizzard_WorldMap/Blizzard_WorldMap.lua` lines 1392 and 1400. Both toggle.
3. **The map opens at the player's zone.** `WorldMapMixin:OnShow` sets `MapUtil.GetDisplayableMapForPlayer()` (`Blizzard_WorldMap.lua` lines 393 and 394). The open itself takes no map. Only `OpenWorldMap(mapID)` does, and no Blizzard button or binding calls it with a map that Seek chooses. (The quest title button below is the exception: it moves the map after the open.)
4. **The quest's title button steers both.** Each quest in the log is a pooled, unnamed title button. A left click calls `QuestMapFrame_ShowQuestDetails(questID)` (`Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua` line 2491). That shows the details, sets the map to the quest's map (`GetQuestUiMapID`), and pings the quest (lines 1094 to 1098). `QuestLogQuests_GetQuestButton(questID)` finds the button (line 1800). So: macro line 1 opens the log, line 2 clicks a proxy whose `PreClick` points it at the quest's title button.
5. **Limits.** A quest under a collapsed header has no title button. The pool may be rebuilt when the log refreshes; the proxy looks it up just before the click. `QuestMapFrame_OpenToQuestDetails` first sets the log's display mode to "Quests" (line 1176); the secure path does not. Forever hides the other modes' tabs (`Camelot/QuestMapFrameOverrides.lua`), so this should not matter.
6. **Combat.** Addon code cannot open the map or quest log in combat (Blizzard shows "Interface action failed because of an AddOn"). The player can (M or L in combat). A prepared secure click works in combat; Seek cannot prepare one in combat.

### Enter from the search bar's text box (question 4)

1. While an EditBox has keyboard focus, key bindings do not fire. So Enter in the search bar's text box cannot reach an override binding.
2. #22's method works without focus: the box gives up focus, a plain keyboard-enabled frame takes the keys, and lets Enter go on to the override binding (`SetPropagateKeyboardInput(true)`). Seek already does this for the action list (`Seek/adapters/wow/SearchBar.lua`).
3. For the main action, the same method would need the box to give up focus when the player moves to a result (for example with Down), and to take it back on a typed letter. The prototype tests the key handling.
4. Untested idea: on Enter's down press, the box gives up focus, and the secure button acts on the up press. Does the up press reach the binding? The prototype tests this too (`/sop box up`).

## The prototype

`prototypes/SecureOpenProbe/` is a separate, **throwaway** addon (`SecureOpenProbe_Camelot.toc`). It is not part of Seek. Delete it when this research is done.

Each command prepares one method out of combat and binds Enter to it. The next Enter press runs it once. Then Enter is normal again. The binding is also cleared by `/sop off`, after 20 seconds, and when combat starts. Chat messages start with "SOP:" and say what happened.

| Command | What it does |
|---|---|
| `/sop bag insecure <itemID>` | Calls `OpenBag` from addon code (Seek today), then the glow. |
| `/sop bag click <itemID>` | Enter: type `click` on the first closed bag's slot button. Then the glow. |
| `/sop bag macro <itemID>` | Enter: a macro with `/click` on each closed bag that holds the item (one for combined bags). Then the glow. |
| `/sop bag bind <itemID>` | Enter: that bag's binding command (`TOGGLEBACKPACK`, `TOGGLEBAG1`...). Then the glow. |
| `/sop bag all` | Enter: the binding `OPENALLBAGS`. |
| `/sop book insecure <spellID>` | Calls `OpenToSpellBookTabAtSpell` from addon code (the removed "show in spellbook"). |
| `/sop book click` | Enter: type `click` on `SpellbookMicroButton`. |
| `/sop book bind [pet]` | Enter: the binding `TOGGLESPELLBOOK` (or `TOGGLEPETBOOK`). |
| `/sop book tabs` | Lists the spellbook's tabs (after it was opened once). |
| `/sop book page <tab> <n>` | Enter: a macro that opens the spellbook, clicks tab `<tab>`, clicks "previous page" back to page 1, then "next page" `<n>` times (0 to 8). It refuses a macro over 255 characters. |
| `/sop log insecure <questID>` | Calls `QuestMapFrame_OpenToQuestDetails` from addon code (Seek's "show in quest log"). |
| `/sop log click` | Enter: type `click` on `QuestLogMicroButton`. |
| `/sop log bind` | Enter: the binding `TOGGLEQUESTLOG`. |
| `/sop log quest <questID>` | Enter: a macro that opens the quest log, then clicks the quest's title button. |
| `/sop map insecure <questID>` | Calls `OpenWorldMap(mapID)` and the quest ping from addon code (Seek's "show on map"). |
| `/sop map bind` | Enter: the binding `TOGGLEWORLDMAP`. |
| `/sop box` | Question 4: a small window with a focused text box. Enter, then Down and Enter. |
| `/sop box up` | Question 4: the box gives up focus on Enter's down press; the button acts on the up press. |
| `/sop pin` | Shows or hides the secure button as a blue square, for mouse clicks (also in combat). It keeps the last method armed with a secure button (not the binding methods). Use it after `/sop off`: while Enter is armed, its messages assume a key press. |
| `/sop status` | Combat state, what Enter does, open bags and windows. |
| `/sop off` | Clears the Enter binding now. |

When a method clicks a Blizzard button, the probe prints whether that button is visible and enabled, and whether it refuses scripted clicks.

## Test plan

### Setup (once)

1. In the project folder: `make link-probe` (the same `WOW_ADDONS` as `make link`).
2. Start the game. In the AddOns list on the character screen, enable **SecureOpenProbe (throwaway)**. Disable **Seek** for these tests, so the taint log shows only the probe.
3. Log in. Type `/sop`. The help lines should show.
4. Turn on the taint log: `/console taintLog 1`. It stays on until you turn it off.
5. The log is `Logs/taint.log` in the WoW Forever folder (next to `Interface`). WoW writes it when you `/reload` or log out.

### Start fresh before each test

1. Close every window.
2. `/reload`. This also flushes the log of the test before.
3. Do not open the window under test by hand before the test. The first open matters (#27, #29).
4. After the test, `/reload` again, then open `Logs/taint.log`. Look for lines that name **SecureOpenProbe**. Copy them into "Results".

### What to check after each open

- **Bags:** use an item by right click in the opened bag. Cast a spell that targets a bag item (for example Feed Pet) and click the item. Did the glow show on the item?
- **Spellbook:** cast a spell from the opened page by clicking it, on a tab other than the first. Then enter combat and use a pet action (the #29 action bar problem).
- **Quest log / map:** close the map. Enter combat. Press M (or L). Do the quest pins show without errors (#38)?
- Any red "action blocked" error in the game. Any line in the taint log that names the probe.

### Tests

For each test: start fresh, type the command, close the chat box, press Enter once with no modifier key held, then do the checks above. (Shift + a bag button opens all bags.)

Methods that toggle (bag buttons, micro buttons, bindings) refuse to arm when their window is already open, and say so.

1. **Baseline (insecure), to see the known taint.** `/sop bag insecure <itemID>`, `/sop book insecure <spellID>` (a spell on another tab), `/sop log insecure <questID>`, `/sop map insecure <questID>`. Each in its own fresh session. Expect the taint from #27, #29, #38.
2. **Bags, secure.** Test `/sop bag click`, `/sop bag macro`, `/sop bag bind`, `/sop bag all`. Use an item that is in two bags, and test with combined bags on and off (the bag menu's settings). With separate bags: did only the bags with the item open? With combined bags: did the combined bag open and stay open?
3. **Bags, item on the cursor.** Pick up an item with the mouse, then run `/sop bag click`. Expected: the item goes into the bag (`PutItemInBag`) instead of opening it. Note what happens.
4. **Spellbook, secure open.** `/sop book click` and `/sop book bind`. Then the spellbook checks.
5. **Spellbook, tab and page.** The tab buttons exist only after the spellbook has loaded. After the fresh start, `/sop book tabs`. If it says "not loaded", open and close the spellbook by hand (that is secure), and write that down in the results. Then `/sop book page <tab> <n>` for a spell on another tab and page. Did it land on the right page? Cast that spell by clicking it. Then the pet action check in combat.
6. **Quest log, secure open.** `/sop log click`, `/sop log bind`, `/sop map bind`. Then the map checks.
7. **Quest log at a quest.** `/sop log quest <questID>` for a quest in another zone. Did the details open? Did the map move to the quest's zone with a ping? Then the map checks. This also answers whether an insecure `PreClick` taints the secure click after it.
8. **Combat, prepared button.** Out of combat: `/sop bag click <itemID>` (or another secure method), then `/sop off`, then `/sop pin`. Enter combat (attack a training dummy or a weak mob). Click the blue square. Did the window open? Any error? Then `/sop pin` after combat to hide it.
9. **Combat, arming.** In combat, type any arming command. Expected: "In combat: cannot prepare". Arm a method out of combat, then enter combat before pressing Enter. Expected: "Enter is normal again (combat started)", and Enter opens chat in combat.
10. **Question 4.** `/sop box`. With the text box focused, press Enter. Expected: "Enter reached the text box". Then press Down: "a plain frame has the keyboard". Press Enter: the backpack should toggle, and the box gets the focus back. Then `/sop box up`: press Enter once (only once). Did "Secure button clicked (... up press)" show? Close with Escape.
11. **Clean-up check.** After any test: `/sop status` should say "Armed: no", and "Enter binding" should be the game's own action (normally `OPENCHAT`), not a probe click or a `TOGGLE...` command. Press Enter: the chat box opens.

When done: `/console taintLog 0`, and disable the probe in the AddOns list.

## Results

To be filled in after the in-game tests. For each test: the command, what opened, the checks, and the taint log lines (or "clean").

### Bags (#27)

_Not tested yet._

### Spellbook (#29)

_Not tested yet._

### Quest log and world map (#38)

_Not tested yet._

### Combat

_Not tested yet._

### Enter from the search bar's text box (question 4)

_Not tested yet._

## Recommendations

To be written after the results: for each of #27, #29, #38, fix fully, fix partly, or keep the action removed.
