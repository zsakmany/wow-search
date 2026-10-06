# Left and Right arrows for the action list

Seek does not use the Left and Right arrow keys to open and close the action list. Right does not open the selected result's action list, and Left does not close it. Tab opens the list, and Escape closes it.

## Why this is out of scope

In the search bar, the text box has the keyboard while the player types the query. There, Left and Right move the cursor in the query. Moving in the query is more important than one more way to open the action list: the player uses it to fix a typo in the middle of a word.

Every version of the idea takes something away from that:

- **Right always opens the list.** Then Right never moves the cursor in the query again.
- **Right opens the list only at the end of the query.** Then the same key does two different things, and which one depends on where the cursor is. A player who presses Right to get to the end of the query opens the list by surprise.
- **Left closes the list.** In combat, the action list works from the text box, so Left would also move the cursor in the query.

Tab and Escape already open and close the action list, and they do nothing else in the search bar.

## What would change this

A search bar where the query and the results have the keyboard at different times, so that the arrow keys could mean different things in each without any doubt.

## Prior requests

- #49: "Right arrow opens the action list, Left arrow closes it"
