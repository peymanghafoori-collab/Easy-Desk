#!/usr/bin/env python3
"""
EasyDesk branding patch for the RustDesk source tree.

Run from the repository root (the folder that contains Cargo.toml):

    python apply_easydesk.py

It is safe to run more than once. It stops with an error if a line it expects
to change can't be found, so a silent half-patched build is not possible.
"""
import re
import shutil
import sys
from pathlib import Path

# ----------------------------- settings ---------------------------------
APP_NAME = "EasyDesk"
SERVER = "sanat.01system.ir"  # ID / rendezvous server (hbbs). Relay (hbbr) is derived from it.
KEY = "7gCWMUOTEbUIQJveXrvhgm2eZvFptk0d9VTG82dawbY="  # contents of id_ed25519.pub
# Address of the ads.json file that controls the ad banners (titles, links, images).
# Leave it empty ("") to build without any ad banner.
ADS_URL = "https://raw.githubusercontent.com/peymanghafoori-collab/Easy-Desk/refs/heads/easy-desk/ads.json"
# -------------------------------------------------------------------------

ROOT = Path.cwd()
ASSETS = Path(__file__).resolve().parent / "easydesk-assets"


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def edit(path, pattern, repl, flags=0):
    p = ROOT / path
    if not p.exists():
        fail(f"{path} not found - run this from the RustDesk repository root")
    text = p.read_text(encoding="utf-8")
    if repl in text:
        print(f"already patched {path}")
        return
    new, n = re.subn(pattern, lambda m: repl, text, count=1, flags=flags)
    if n != 1:
        fail(f"pattern not found in {path}: {pattern}")
    if new != text:
        p.write_text(new, encoding="utf-8")
    print(f"patched {path}")


def copy_asset(src, dst):
    s = ASSETS / src
    d = ROOT / dst
    if not s.exists():
        fail(f"missing asset {s}")
    d.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(s, d)
    print(f"copied  {dst}")


if not (ROOT / "Cargo.toml").exists():
    fail("Cargo.toml not found - run this from the RustDesk repository root")

# 1) name, server and key (libs/hbb_common is a git submodule: patched in the
#    working tree at build time, nothing needs to be committed to it)
cfg = "libs/hbb_common/src/config.rs"
edit(cfg, r'RwLock::new\("RustDesk"\.to_owned\(\)\)', f'RwLock::new("{APP_NAME}".to_owned())')
edit(cfg, r'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];',
     f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{SERVER}"];')
edit(cfg, r'pub const RS_PUB_KEY: &str = "[^"]*";', f'pub const RS_PUB_KEY: &str = "{KEY}";')

# 2) Windows file properties shown in Explorer / Task Manager
rc = "flutter/windows/runner/Runner.rc"
edit(rc, r'VALUE "CompanyName", "[^"]*"', f'VALUE "CompanyName", "{APP_NAME}"')
edit(rc, r'VALUE "FileDescription", "[^"]*"', f'VALUE "FileDescription", "{APP_NAME} Remote Desktop"')
edit(rc, r'VALUE "ProductName", "[^"]*"', f'VALUE "ProductName", "{APP_NAME}"')
edit(rc, r'VALUE "InternalName", "[^"]*"', f'VALUE "InternalName", "{APP_NAME}"')
edit(rc, r'VALUE "OriginalFilename", "[^"]*"', f'VALUE "OriginalFilename", "{APP_NAME}.exe"')

# same for the self-extracting installer (the single .exe people double-click)
portable = "libs/portable/Cargo.toml"
edit(portable, r'ProductName = "[^"]*"', f'ProductName = "{APP_NAME}"')
edit(portable, r'OriginalFilename = "[^"]*"', f'OriginalFilename = "{APP_NAME}.exe"')
edit(portable, r'FileDescription = "[^"]*"', f'FileDescription = "{APP_NAME} Remote Desktop"')

# 3) icons and logos
for name in ("icon.ico", "tray-icon.ico", "32x32.png", "64x64.png", "128x128.png",
             "128x128@2x.png", "icon.png", "mac-icon.png"):
    copy_asset(name, f"res/{name}")
copy_asset("easydesk-icon.svg", "res/logo.svg")
copy_asset("easydesk-icon.svg", "res/scalable.svg")
copy_asset("app_icon.ico", "flutter/windows/runner/resources/app_icon.ico")
copy_asset("icon.ico", "flutter/assets/icon.ico")  # used by the installer for shortcuts
copy_asset("easydesk-icon.svg", "flutter/assets/icon.svg")

# 4) dynamic ad banner on the home page (content comes from ADS_URL at run time)
if ADS_URL:
    if not ADS_URL.startswith("https://") or "'" in ADS_URL or "$" in ADS_URL:
        fail("ADS_URL must start with https:// and must not contain ' or $")
    widget_src = (ASSETS / "easydesk_ad_banner.dart").read_text(encoding="utf-8")
    if "__ADS_URL__" not in widget_src:
        fail("easydesk_ad_banner.dart has no __ADS_URL__ placeholder")
    widget_dst = ROOT / "flutter/lib/desktop/widgets/easydesk_ad_banner.dart"
    widget_dst.write_text(widget_src.replace("__ADS_URL__", ADS_URL), encoding="utf-8")
    print("wrote   flutter/lib/desktop/widgets/easydesk_ad_banner.dart")

    home = ROOT / "flutter/lib/desktop/pages/desktop_home_page.dart"
    if not home.exists():
        fail("desktop_home_page.dart not found")
    home_text = home.read_text(encoding="utf-8")
    if "EasyDeskAdBanner" in home_text:
        print("already patched desktop_home_page.dart")
    else:
        imp = "import '../widgets/button.dart';\n"
        if home_text.count(imp) != 1:
            fail("import anchor not found in desktop_home_page.dart")
        home_text = home_text.replace(imp, imp + "import '../widgets/easydesk_ad_banner.dart';\n")
        # add the banner as the last item of the left pane, after the ID/password boards
        anchor = re.compile(
            r"(      \),\n)(    \];\n    if \(isIncomingOnly\) \{\n      children\.addAll\(\[)")
        home_text, n = anchor.subn(
            lambda m: m.group(1) + "      const EasyDeskAdBanner(),\n" + m.group(2),
            home_text, count=1)
        if n != 1:
            fail("left pane anchor not found in desktop_home_page.dart")
        home.write_text(home_text, encoding="utf-8")
        print("patched flutter/lib/desktop/pages/desktop_home_page.dart")

print(f"\nDone: {APP_NAME} -> server {SERVER}")
