#!/bin/sh
# Renders the optional app icons in Scripts/app-icons/*.svg into the asset catalog.
# These are the ones selectable in Settings > Appearance. The default icon is the
# bundle's AppIcon.appiconset, which this script leaves alone.
# To add another: draw <name>.svg on the same 1024 canvas (824 plate, 100 margin),
# add an `alternate` line below, and add a case to IRCAppIcon.
# Requires rsvg-convert (brew install librsvg).
set -eu

cd "$(dirname "$0")/app-icons"
assets="../../Netsplit/Netsplit/Assets.xcassets"

render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

alternate() {
    set_dir="$assets/$2.imageset"
    mkdir -p "$set_dir"
    render "$1" 512 "$set_dir/$2.png"
    render "$1" 1024 "$set_dir/$2@2x.png"
    cat > "$set_dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$2.png",
      "idiom" : "mac",
      "scale" : "1x"
    },
    {
      "filename" : "$2@2x.png",
      "idiom" : "mac",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

alternate bubble.svg AppIconBubble
