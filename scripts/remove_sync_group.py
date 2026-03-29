#!/usr/bin/env python3
"""
Remove PBXFileSystemSynchronizedRootGroup that Xcode 16 auto-created.
This group causes every file to appear twice (once via sync, once via explicit ref).
Keep explicit file references added by setup_xcodeproj.py.
"""

import re
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, 'Voxema.xcodeproj', 'project.pbxproj')

data = open(PBXPROJ).read()
original = data

# ── 1. Find PBXFileSystemSynchronizedRootGroup IDs ────────────────────────
sync_ids = re.findall(r'([A-F0-9]{24})\s*/\*[^*]*\*/\s*=\s*\{[^}]*isa\s*=\s*PBXFileSystemSynchronizedRootGroup[^}]*\}', data)
print(f"Found {len(sync_ids)} PBXFileSystemSynchronizedRootGroup entries: {sync_ids}")

# ── 2. Remove the section entirely ────────────────────────────────────────
data = re.sub(
    r'/\* Begin PBXFileSystemSynchronizedRootGroup section \*/.*?/\* End PBXFileSystemSynchronizedRootGroup section \*/',
    '',
    data,
    flags=re.DOTALL
)

# ── 3. Remove references to sync group IDs from all parent groups ─────────
for sid in sync_ids:
    # Remove "ID /* Name */," or "ID /* Name */\n" references in group children lists
    data = re.sub(r'\s*' + sid + r'\s*/\*[^*]*\*/,?', '', data)
    print(f"  Removed references to {sid}")

# ── 4. Also remove PBXFileSystemSynchronizedBuildFileExceptionSet if any ──
if 'PBXFileSystemSynchronizedBuildFileExceptionSet' in data:
    data = re.sub(
        r'/\* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section \*/.*?/\* End PBXFileSystemSynchronizedBuildFileExceptionSet section \*/',
        '',
        data,
        flags=re.DOTALL
    )
    print("  Removed PBXFileSystemSynchronizedBuildFileExceptionSet section")

# ── 5. Write back ──────────────────────────────────────────────────────────
with open(PBXPROJ, 'w') as f:
    f.write(data)

changed = data != original
print(f"\n{'Modified' if changed else 'No changes made to'}: {PBXPROJ}")
