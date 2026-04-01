#!/usr/bin/env python3
"""
scripts/add_coreml_ecapa.py  —  TASK-29

Modifies project.pbxproj to replace voxema_ecapa_mfcc.c with
voxema_ecapa_coreml.m and add CoreML.framework.

Also optionally bundles ecapa-tdnn.mlpackage if the file already exists at
Voxema/Resources/Models/ecapa-tdnn.mlpackage.

Run ONCE after converting the model (or without the model file — code changes
are applied regardless; the mlpackage entry is skipped when the file is absent).

    python3 scripts/add_coreml_ecapa.py
"""

import os
import sys

ROOT    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, 'Voxema.xcodeproj', 'project.pbxproj')
MODEL_PATH = os.path.join(ROOT, 'Voxema', 'Resources', 'Models', 'ecapa-tdnn.mlpackage')

with open(PBXPROJ, 'r', encoding='utf-8') as f:
    src = f.read()

# ── Guard: skip if already patched ───────────────────────────────────────────
if 'voxema_ecapa_coreml.m' in src:
    print("Already patched — voxema_ecapa_coreml.m reference found. Exiting.")
    sys.exit(0)

has_model = os.path.isdir(MODEL_PATH)
if has_model:
    print(f"Found {MODEL_PATH} — will bundle in Resources.")
else:
    print(f"Model not found at {MODEL_PATH} — code-only patch applied.")
    print("  Run convert_ecapa_coreml.py first, then re-run this script.")

# ── Stable IDs ────────────────────────────────────────────────────────────────
ID_REF_COREML_M   = 'CDED1122334455667788AACC'   # voxema_ecapa_coreml.m file ref
ID_BF_COREML_M    = 'CDED1122334455667788AACB'   # voxema_ecapa_coreml.m in Sources
ID_REF_COREML_FW  = 'CDED1122334455667788AACD'   # CoreML.framework file ref
ID_BF_COREML_FW   = 'CDED1122334455667788AACE'   # CoreML.framework in Frameworks
ID_REF_MLPKG      = 'CDED1122334455667788AACF'   # ecapa-tdnn.mlpackage file ref
ID_BF_MLPKG       = 'CDED1122334455667788AAD0'   # ecapa-tdnn.mlpackage in Resources

# Existing IDs we need to reference / remove
ID_BF_MFCC_SOURCES = 'ACCE1122334455667788AABB'   # mfcc.c in Sources (to replace)
ID_REF_MFCC        = 'ACCE1122334455667788AABD'   # mfcc.c file ref (kept in project)
ID_BF_ACCELERATE   = 'ACCE1122334455667788AABC'   # Accelerate.framework in Frameworks

# ── 1. PBXFileReference entries ───────────────────────────────────────────────
# Insert before "/* End PBXFileReference section */"

mlpkg_ref = ''
if has_model:
    mlpkg_ref = f'\n\t\t{ID_REF_MLPKG} /* ecapa-tdnn.mlpackage */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; name = "ecapa-tdnn.mlpackage"; path = "Voxema/Resources/Models/ecapa-tdnn.mlpackage"; sourceTree = SOURCE_ROOT; }};'

file_refs = (
    f'\t\t{ID_REF_COREML_M} /* voxema_ecapa_coreml.m */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.objc; name = voxema_ecapa_coreml.m; path = Voxema/Bridge/COnnxRuntime/voxema_ecapa_coreml.m; sourceTree = SOURCE_ROOT; }};\n'
    f'\t\t{ID_REF_COREML_FW} /* CoreML.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = CoreML.framework; path = System/Library/Frameworks/CoreML.framework; sourceTree = SDKROOT; }};'
    f'{mlpkg_ref}\n'
    '/* End PBXFileReference section */'
)
src = src.replace('/* End PBXFileReference section */', file_refs, 1)
print('✓ PBXFileReference entries injected')

# ── 2. PBXBuildFile entries ───────────────────────────────────────────────────
# Replace the mfcc.c build-file entry with coreml.m + CoreML.framework (+mlpackage)

mlpkg_bf = ''
if has_model:
    mlpkg_bf = f'\n\t\t{ID_BF_MLPKG} /* ecapa-tdnn.mlpackage in Resources */ = {{isa = PBXBuildFile; fileRef = {ID_REF_MLPKG} /* ecapa-tdnn.mlpackage */; }};'

old_mfcc_bf = f'\t\t{ID_BF_MFCC_SOURCES} /* voxema_ecapa_mfcc.c in Sources */ = {{isa = PBXBuildFile; fileRef = {ID_REF_MFCC} /* voxema_ecapa_mfcc.c */; }};'
new_bf = (
    f'\t\t{ID_BF_COREML_M} /* voxema_ecapa_coreml.m in Sources */ = {{isa = PBXBuildFile; fileRef = {ID_REF_COREML_M} /* voxema_ecapa_coreml.m */; }};\n'
    f'\t\t{ID_BF_COREML_FW} /* CoreML.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {ID_REF_COREML_FW} /* CoreML.framework */; }};'
    f'{mlpkg_bf}'
)
src = src.replace(old_mfcc_bf, new_bf, 1)
print('✓ PBXBuildFile entries injected')

# ── 3. Sources build phase: replace mfcc.c with coreml.m ─────────────────────
old_sources_entry = f'\t\t\t\t{ID_BF_MFCC_SOURCES} /* voxema_ecapa_mfcc.c in Sources */,'
new_sources_entry = f'\t\t\t\t{ID_BF_COREML_M} /* voxema_ecapa_coreml.m in Sources */,'
src = src.replace(old_sources_entry, new_sources_entry, 1)
print('✓ Sources phase updated (mfcc.c → coreml.m)')

# ── 4. Frameworks build phase: add CoreML.framework ──────────────────────────
# Insert after Accelerate.framework (which we know is there)
old_fw_anchor = f'\t\t\t\t{ID_BF_ACCELERATE} /* Accelerate.framework in Frameworks */,'
new_fw_entry  = (
    f'\t\t\t\t{ID_BF_COREML_FW} /* CoreML.framework in Frameworks */,\n'
    f'\t\t\t\t{ID_BF_ACCELERATE} /* Accelerate.framework in Frameworks */,'
)
src = src.replace(old_fw_anchor, new_fw_entry, 1)
print('✓ Frameworks phase updated (CoreML.framework added)')

# ── 5. Resources build phase: add mlpackage (if file exists) ─────────────────
if has_model:
    # Anchor on models-manifest.json entry in Resources phase
    RESOURCES_ANCHOR = '\t\t\t\tA27B4219CEE1433381449F00 /* models-manifest.json in Resources */,'
    new_res_entry = (
        f'\t\t\t\t{ID_BF_MLPKG} /* ecapa-tdnn.mlpackage in Resources */,\n'
        f'\t\t\t\tA27B4219CEE1433381449F00 /* models-manifest.json in Resources */,'
    )
    src = src.replace(RESOURCES_ANCHOR, new_res_entry, 1)
    print('✓ Resources phase updated (ecapa-tdnn.mlpackage added)')

# ── 6. PBXGroup: add coreml.m alongside mfcc.c ───────────────────────────────
old_group_anchor = f'\t\t\t\t{ID_REF_MFCC} /* voxema_ecapa_mfcc.c */,'
new_group_entry = (
    f'\t\t\t\t{ID_REF_COREML_M} /* voxema_ecapa_coreml.m */,\n'
    f'\t\t\t\t{ID_REF_MFCC} /* voxema_ecapa_mfcc.c */,'
)
src = src.replace(old_group_anchor, new_group_entry, 1)
print('✓ PBXGroup updated (coreml.m added to COnnxRuntime group)')

# ── 7. Models PBXGroup: add mlpackage (if file exists) ───────────────────────
if has_model:
    old_models_anchor = '\t\t\t\t6AC8C9D953764CD2B350BB0A /* models-manifest.json */,'
    new_models_entry  = (
        f'\t\t\t\t{ID_REF_MLPKG} /* ecapa-tdnn.mlpackage */,\n'
        '\t\t\t\t6AC8C9D953764CD2B350BB0A /* models-manifest.json */,'
    )
    src = src.replace(old_models_anchor, new_models_entry, 1)
    print('✓ Models PBXGroup updated (ecapa-tdnn.mlpackage added)')

# ── Write ─────────────────────────────────────────────────────────────────────
with open(PBXPROJ, 'w', encoding='utf-8') as f:
    f.write(src)

print('\n✓ project.pbxproj updated successfully.')
if not has_model:
    print('\nTo bundle the CoreML model:')
    print('  1. python3 scripts/convert_ecapa_coreml.py')
    print('  2. mv ecapa-tdnn.mlpackage Voxema/Resources/Models/')
    print('  3. python3 scripts/add_coreml_ecapa.py   (re-run this script)')
print('\nBuild in Xcode to verify.')
