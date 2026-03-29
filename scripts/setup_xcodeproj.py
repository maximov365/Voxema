#!/usr/bin/env python3
"""
FIX-1: Wire all source files into Voxema.xcodeproj, fix build settings.
Run from the repository root: python3 scripts/setup_xcodeproj.py
"""

import os
import sys

try:
    from pbxproj import XcodeProject
    from pbxproj.pbxextensions import TreeType
except ImportError:
    print("ERROR: pbxproj not installed. Run: pip3 install pbxproj --break-system-packages")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_PATH = os.path.join(ROOT, 'Voxema.xcodeproj', 'project.pbxproj')

print(f"Opening: {PROJECT_PATH}")
project = XcodeProject.load(PROJECT_PATH)

TARGET = 'Voxema'

# ── 1. Collect all Swift source files ────────────────────────────────────
swift_files = []
for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, 'Voxema')):
    # Skip Xcode-created files at root of Voxema/ (they're in App/ now)
    for fname in sorted(filenames):
        if fname.endswith('.swift'):
            full = os.path.join(dirpath, fname)
            swift_files.append(full)

print(f"\nFound {len(swift_files)} Swift files:")
for f in swift_files:
    print(f"  {os.path.relpath(f, ROOT)}")

# ── 2. Add files to project ───────────────────────────────────────────────
print("\nAdding files to Xcode project...")
for filepath in swift_files:
    try:
        project.add_file(filepath, target_name=TARGET, tree=TreeType.SOURCE_ROOT)
        print(f"  + {os.path.relpath(filepath, ROOT)}")
    except Exception as e:
        print(f"  ~ skipped {os.path.relpath(filepath, ROOT)}: {e}")

# ── 3. Fix build settings ─────────────────────────────────────────────────
print("\nApplying build settings...")

settings = {
    'MACOSX_DEPLOYMENT_TARGET': '13.0',
    'SWIFT_VERSION': '5.0',
    'ENABLE_HARDENED_RUNTIME': 'YES',
    'CODE_SIGN_ENTITLEMENTS': 'Voxema/Voxema.entitlements',
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.voxema.Voxema',
    'INFOPLIST_FILE': 'Voxema/Info.plist',
}

for key, value in settings.items():
    project.set_flags(key, value, target_name=TARGET)
    print(f"  {key} = {value}")

# Also fix project-level deployment target
project.set_flags('MACOSX_DEPLOYMENT_TARGET', '13.0')

# ── 4. Save ────────────────────────────────────────────────────────────────
project.save()
print(f"\nSaved: {PROJECT_PATH}")
print("Done.")
