# DMG layout settings for UVieKey
# Usage: dmgbuild -s scripts/dmgbuild_settings.py -D app=UVieKey.app "UVieKey <version>" UVieKey-<version>-universal.dmg

import os
import plistlib

application = defines.get("app", "UVieKey.app")
appname = os.path.basename(application)


def icon_from_app(app_path):
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    with open(plist_path, "rb") as f:
        plist = plistlib.load(f)
    icon_name = plist.get("CFBundleIconFile", "AppIcon")
    icon_root, icon_ext = os.path.splitext(icon_name)
    if not icon_ext:
        icon_ext = ".icns"
    icon_name = icon_root + icon_ext
    return os.path.join(app_path, "Contents", "Resources", icon_name)


# Volume icon
badge_icon = icon_from_app(application)

# Files to include
files = [application]

# Symlinks to create
symlinks = {"Applications": "/Applications"}

# Window appearance
window_rect = ((200, 120), (600, 340))
default_view = "icon-view"

icon_size = 128
text_size = 16
label_pos = "bottom"
arrange_by = None

# Icon positions: app bundle on the left, Applications shortcut on the right
icon_locations = {
    appname: (150, 170),
    "Applications": (450, 170),
}

# Hide .app extension for a cleaner look
hide_extensions = [appname]

# Disk image format
format = "UDZO"
filesystem = "HFS+"
