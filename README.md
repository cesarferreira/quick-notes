# Quick Notes

A little space for your thoughts. A native macOS menu bar notepad with the same
floating glass feel as Quick Ask, and a live Markdown editor inspired by Raycast
Notes.

<p align="center">
  <img alt="Quick Notes demo: swiping between notes, tracking checklist progress, and browsing history" src="demo.gif" width="800">
</p>

Open it from the menu bar, or [bind a global key with kiwi](#toggle-it-with-a-hotkey-kiwi)
to open or dismiss it from any app. Write a thought,
make a checklist, or find something in your note history. Everything saves on your
Mac as plain Markdown. No account or network connection is needed.

## Build and run

Requires macOS 14 or newer and Xcode command line tools with Swift 6. The panel
uses dark native macOS vibrancy with a soft wallpaper tint and a subtle rounded border.
The project uses Swift and AppKit with no external dependencies. Quick Ask’s
Rust/GPUI project is kept separate; AppKit provides the editable native text view.

```sh
make run
```

To create an app bundle:

```sh
make package
open "dist/Quick Notes.app"
```

For a quicker development bundle, run `./scripts/package.sh --debug`. To package,
install in `/Applications`, and launch, run `make install`. Override the install
location with `make install INSTALL_DIR=~/Applications`.

## Toggle it with a hotkey (kiwi)

Quick Notes has no global shortcut of its own.
[kiwi](https://github.com/cesarferreira/kiwi) can show and hide it with one key.
Install the app first (`make install`), then add a binding to
`~/.config/kiwi/config.toml`:

```toml
[bindings]
"hyper+q" = { command = "'/Applications/Quick Notes.app/Contents/MacOS/quick-notes' --toggle" }

# Or double-tap right Command.
"double+right_command" = { command = "'/Applications/Quick Notes.app/Contents/MacOS/quick-notes' --toggle" }
```

`hyper` is the modifier you define in kiwi's `[hyper]` section (for example Caps
Lock). Each press toggles the panel's visibility, including when it is pinned
above another app. The command launches Quick Notes if it is not running, and
otherwise sends the running app a toggle request without opening a second panel.

Use this command binding instead of kiwi's generic `app` toggle: the notes panel
can remain visible while another app is frontmost. kiwi reloads the config
automatically. If you installed somewhere other than `/Applications`, adjust the
command path to that location.

## Writing

Type Markdown directly. Headings, **bold**, *italic*, `inline code`,
~~strikethrough~~, and HTTP/HTTPS Markdown links format as you type. Formatting
markers are hidden in formatted mode and remain intact in the saved `.md` file.
Unordered and numbered list markers remain visible. Fenced code is monospaced
and its contents are left literal.

Both task syntaxes become clickable checkboxes after the trailing space:

```md
[ ] Create release
[ ] Merge 2 PRs
  - [ ] PR 1
  - [x] PR 2
```

- Click a checkbox to toggle it. Completed items get a strikethrough.
- Press **Return** to continue a task or list. Return on an empty item ends it.
- Use **Tab** and **Shift+Tab** to indent or outdent selected lines.
- Press **Command+Shift+M** to see and edit the original Markdown.
- The **T** button opens formatting, text size, copy, and file options.

Notes with tasks show a completed count, percentage, and progress bar above the
footer. Progress updates as you edit or check tasks. Nested tasks count
individually; checkbox examples inside fenced code blocks are ignored.

This is a small Markdown notepad: tables, embedded images, HTML, and a full
CommonMark renderer are outside this version’s scope. Text always stays editable.

## Notes and history

Click **+** or press **Command+N** for a new note. The first nonempty line becomes
its title. Click the history icon or press **Command+H** to search all saved note
text, with the most recently modified notes first. Search ignores case and
accents. Click a result or press Return to open it; use Down to enter the results
and the arrow keys to choose one. Escape returns to the editor.

Swipe **left** inside a note to open the next older note, or **right** to return
to a newer note. Each swipe moves one note in last-edited order; vertical scrolling
still scrolls the current note. Edits save before switching. The browsing order
stays fixed while you swipe, and stops at the oldest or newest note. Starting a
new note or choosing one from the history list refreshes that order.

Edits save automatically after a brief pause and before switching notes, closing
the panel, or quitting. Blank new notes do not clutter history. The footer shows
the character count and save status. If a save fails, the panel keeps your draft
and shows the error. If a file changed outside the app, your version saves as a
separate note so both versions survive. This history is a list of notes, rather
than a revision timeline for each note.

The panel stays above other windows by default, so you can refer to a note while
working in another app. Click the pin to switch to dismissing when focus leaves.
Your pin preference is remembered between launches.
The panel springs open and fades closed, swiping slides between notes, and history
crossfades into place. Checkboxes draw their ticks with a small bounce, and toolbar
buttons respond to hovering and pressing. Typing and saving stay immediate; the
animations follow the macOS Reduce Motion preference.
Drag the header to move it and the window edges to resize it. Its size and position
are remembered. Escape always dismisses the editor. Quick Notes remains in the
menu bar until you quit.

| Shortcut | Action |
| --- | --- |
| Command+N | New note |
| Command+H | Note history |
| Command+S | Save now |
| Command+B / Command+I | Bold / italic selection |
| Command+Shift+L | Turn the current line into a task, or toggle it |
| Command+Shift+M | Toggle Markdown source |
| Command+Shift+C | Copy the whole note as Markdown |
| Command+Plus / Command+Minus | Larger / smaller text |
| Command+W / Escape | Hide the panel |
| Command+Q | Quit |

The menu bar menu also offers new note, history, the notes folder, and quit.
A second instance brings the existing app forward.

## Local files

Notes live in:

```text
~/Library/Application Support/Quick Notes/notes/
```

Each note is a UTF-8 `.md` file with a stable filename. Its title comes from its
contents, so renaming a title doesn’t break the file path. Files are atomically
replaced when saving, with owner-only permissions. They are readable local text,
not encrypted storage. There is no database or separate history index. You can
back up the directory or edit files in another editor. External edits refresh
when the panel opens. Do not rename or move a file while editing it in the app;
unsaved edits will become a separate note if its original file disappears.

Use **T → Open notes folder** to reveal the directory. **Move note to Trash**
uses macOS Trash, so deleted notes can be recovered in Finder.

For development or a separate notes collection, launch with a custom directory:

```sh
QUICK_NOTES_DIRECTORY=/path/to/notes swift run quick-notes
```

Quit the current instance first. The directory’s hidden `.app.lock` prevents
multiple app instances from writing to the same notes collection. Window and text
size preferences use macOS user defaults.

## Verification

```sh
make test
swift build -c release
./scripts/package.sh
codesign --verify --deep --strict "dist/Quick Notes.app"
```

Tests cover Markdown offsets and task continuation, filesystem round trips,
search/order, external edit protection, and native text editing, checkbox clicks,
undo, nesting, source mode, and reopening notes from history.
