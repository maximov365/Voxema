#!/usr/bin/env python3
"""
Fix Voxema.xcodeproj build issues:
1. Remove duplicate sources from Compile Sources phase
2. Remove .gitkeep and Info.plist from Copy Bundle Resources phase
3. Set ENABLE_APP_SANDBOX = NO
"""

import os
import sys

try:
    from pbxproj import XcodeProject
except ImportError:
    print("ERROR: pbxproj not installed.")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_PATH = os.path.join(ROOT, 'Voxema.xcodeproj', 'project.pbxproj')

project = XcodeProject.load(PROJECT_PATH)
target = None
for t in project.objects.get_targets('Voxema'):
    target = t
    break

if target is None:
    print("ERROR: Target 'Voxema' not found")
    sys.exit(1)

# ── 1. Fix ENABLE_APP_SANDBOX ─────────────────────────────────────────────
project.set_flags('ENABLE_APP_SANDBOX', 'NO', target_name='Voxema')
project.set_flags('ENABLE_APP_SANDBOX', 'NO')
print("Set ENABLE_APP_SANDBOX = NO")

# ── 2. Deduplicate Compile Sources phase ──────────────────────────────────
# Find the compile sources build phase
compile_phase = None
for phase_id in target.buildPhases:
    phase = project.objects[phase_id]
    if phase.isa == 'PBXSourcesBuildPhase':
        compile_phase = phase
        break

if compile_phase:
    seen_files = set()
    to_remove = []
    for file_id in list(compile_phase.files):
        build_file = project.objects[file_id]
        file_ref_id = build_file.fileRef
        if file_ref_id in seen_files:
            to_remove.append(file_id)
        else:
            seen_files.add(file_ref_id)
    
    for file_id in to_remove:
        compile_phase.files.remove(file_id)
        del project.objects[file_id]
    
    print(f"Removed {len(to_remove)} duplicate entries from Compile Sources phase")
else:
    print("WARNING: Compile Sources phase not found")

# ── 3. Clean Copy Bundle Resources phase ──────────────────────────────────
resources_phase = None
for phase_id in target.buildPhases:
    phase = project.objects[phase_id]
    if phase.isa == 'PBXResourcesBuildPhase':
        resources_phase = phase
        break

EXCLUDED_FROM_RESOURCES = {'.gitkeep', 'Info.plist'}

if resources_phase:
    to_remove = []
    for file_id in list(resources_phase.files):
        build_file = project.objects[file_id]
        file_ref_id = build_file.fileRef
        file_ref = project.objects.get(file_ref_id)
        if file_ref and hasattr(file_ref, 'path'):
            fname = os.path.basename(file_ref.path or '')
            if fname in EXCLUDED_FROM_RESOURCES:
                to_remove.append(file_id)
                print(f"  Removing '{fname}' from Copy Bundle Resources")
    
    for file_id in to_remove:
        resources_phase.files.remove(file_id)
        del project.objects[file_id]
    
    print(f"Removed {len(to_remove)} entries from Copy Bundle Resources phase")
else:
    print("WARNING: Copy Bundle Resources phase not found")

# ── 4. Save ────────────────────────────────────────────────────────────────
project.save()
print(f"\nSaved. Done.")
