#!/bin/bash
# Prints the versions the About view shows under "Built with", tab-separated
# on one line:
#   quickshell  qt  omarchy
# A field is empty when its tool is missing or says nothing useful. Runs only
# when the About view opens; it reads local tools and never touches the network.

quickshell_version=$(quickshell --version 2>/dev/null | head -n1 | awk '$1 == "Quickshell" { print $2 }')

qtpaths=$(command -v qtpaths6 || command -v qtpaths || echo /usr/lib/qt6/bin/qtpaths6)
qt_version=$("$qtpaths" --qt-version 2>/dev/null | head -n1)

omarchy_version=$(omarchy version 2>/dev/null | head -n1)

printf '%s\t%s\t%s\n' "$quickshell_version" "$qt_version" "$omarchy_version"
