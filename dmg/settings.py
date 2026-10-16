# dmgbuild settings for the EXdl installer image. Used by make_dmg.sh, which passes
# the app bundle and the background through `-D name=value`.
#
# The background is rendered by dmg/generate_background.swift; its size and the icon
# row height must stay in sync with the values below.

import os

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
compression_level = 9

files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # background@2x.png next to it is picked up automatically

# Finder window: 660x400 content area below a 28 pt title bar. Newer macOS versions
# draw a slightly taller title bar and crop a few points off the bottom of the
# background, which is plain gradient. The origin is measured from the bottom-left
# of the screen.
CONTENT_SIZE = (660, 400)
TITLE_BAR = 28
window_rect = ((200, 300), (CONTENT_SIZE[0], CONTENT_SIZE[1] + TITLE_BAR))

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)

# Icon centres, measured from the top-left of the content area.
icon_locations = {
    app_name: (185, 238),
    "Applications": (475, 238),
}

# Hidden files only show up when "Show hidden files" is on, but Finder then draws them
# and counts them when sizing the scrollable area. Park them just right of the window
# so they never cover the design; the only side effect is a scrollbar for those users.
for hidden, y in ((".DS_Store", 60), (".background.tiff", 130), (".fseventsd", 200)):
    icon_locations[hidden] = (730, y)


def create_hook(mount_point, options):
    # Keep fseventsd from writing event logs into the image.
    directory = os.path.join(mount_point, ".fseventsd")
    os.makedirs(directory, exist_ok=True)
    for name in os.listdir(directory):
        if name != "no_log":
            os.remove(os.path.join(directory, name))
    open(os.path.join(directory, "no_log"), "w").close()
