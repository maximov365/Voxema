#!/usr/bin/env python3
"""
TASK-27: Enable Metal GPU acceleration for whisper.cpp v1.5.5.

Modifies project.pbxproj via direct string injection (no pbxproj library API needed).

Changes:
  1. PBXFileReference entries for ggml-metal.h / .m / .metal + Metal.framework
  2. PBXBuildFile entries for ggml-metal.m, ggml-metal.metal (Sources), Metal.framework (Frameworks)
  3. ggml-metal.m + ggml-metal.metal added to Compile Sources phase
  4. Metal.framework added to Frameworks phase
  5. OTHER_CFLAGS  = "-DGGML_USE_METAL" in Debug + Release configs
  6. OTHER_CPLUSPLUSFLAGS = "-DGGML_USE_METAL" in Debug + Release configs

Runtime behaviour:
  ggml-metal.m checks [NSBundle bundleForClass:[GGMLMetalClass class]] for default.metallib.
  Xcode compiles ggml-metal.metal → default.metallib → embedded in app bundle Resources.
  No GGML_METAL_EMBED_LIBRARY / pre-build script needed.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, 'Voxema.xcodeproj', 'project.pbxproj')

with open(PBXPROJ, 'r', encoding='utf-8') as f:
    src = f.read()

# ── Guard: skip if already patched ───────────────────────────────────────────
if 'ggml-metal.m' in src:
    print("Already patched — ggml-metal.m reference found. Exiting.")
    sys.exit(0)

# ── IDs (stable, chosen to be unique in this project) ────────────────────────
ID_REF_METAL_H   = 'A1B2C3D4E5F601020304A1B2'
ID_REF_METAL_M   = 'A1B2C3D4E5F601020304A1B3'
ID_REF_METAL_MTL = 'A1B2C3D4E5F601020304A1B4'
ID_REF_METAL_FW  = 'A1B2C3D4E5F601020304A1B5'

ID_BF_METAL_M    = 'B1C2D3E4F5A601020304B1C2'   # ggml-metal.m  → Sources
ID_BF_METAL_MTL  = 'B1C2D3E4F5A601020304B1C3'   # ggml-metal.metal → Sources
ID_BF_METAL_FW   = 'B1C2D3E4F5A601020304B1C4'   # Metal.framework → Frameworks

# ── 1. PBXFileReference entries ───────────────────────────────────────────────
file_refs = f"""\
		{ID_REF_METAL_H} /* ggml-metal.h */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.h; name = "ggml-metal.h"; path = Voxema/Bridge/CWhisper/src/ggml-metal.h; sourceTree = SOURCE_ROOT; }};
		{ID_REF_METAL_M} /* ggml-metal.m */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.objc; name = "ggml-metal.m"; path = Voxema/Bridge/CWhisper/src/ggml-metal.m; sourceTree = SOURCE_ROOT; }};
		{ID_REF_METAL_MTL} /* ggml-metal.metal */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.metal; name = "ggml-metal.metal"; path = Voxema/Bridge/CWhisper/src/ggml-metal.metal; sourceTree = SOURCE_ROOT; }};
		{ID_REF_METAL_FW} /* Metal.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Metal.framework; path = System/Library/Frameworks/Metal.framework; sourceTree = SDKROOT; }};
/* End PBXFileReference section */"""

src = src.replace('/* End PBXFileReference section */', file_refs, 1)
print("✓ PBXFileReference entries injected")

# ── 2. PBXBuildFile entries ───────────────────────────────────────────────────
# Inject before an existing build file entry (ggml-backend.c) as anchor
build_files = f"""\
		{ID_BF_METAL_M} /* ggml-metal.m in Sources */ = {{isa = PBXBuildFile; fileRef = {ID_REF_METAL_M} /* ggml-metal.m */; }};
		{ID_BF_METAL_MTL} /* ggml-metal.metal in Sources */ = {{isa = PBXBuildFile; fileRef = {ID_REF_METAL_MTL} /* ggml-metal.metal */; }};
		{ID_BF_METAL_FW} /* Metal.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {ID_REF_METAL_FW} /* Metal.framework */; }};
		D59378D9034D4852AF46C8FD /* ggml-backend.c in Sources */"""

src = src.replace(
    '\t\tD59378D9034D4852AF46C8FD /* ggml-backend.c in Sources */',
    build_files,
    1
)
print("✓ PBXBuildFile entries injected")

# ── 3. Add to Compile Sources phase ──────────────────────────────────────────
# Find the Sources build phase files list and append before the closing paren
# Anchor: the ggml-backend.c entry in the Sources files list
sources_anchor = 'D59378D9034D4852AF46C8FD /* ggml-backend.c in Sources */,'
sources_insertion = f"""\
				{ID_BF_METAL_M} /* ggml-metal.m in Sources */,
				{ID_BF_METAL_MTL} /* ggml-metal.metal in Sources */,
				D59378D9034D4852AF46C8FD /* ggml-backend.c in Sources */,"""

# The sources phase uses the build file ID in its files array
# Find the Sources phase block and add entries
# The Sources phase files array contains entries like:
#   XXXX /* SomeFile.swift in Sources */,
# We inject before the closing of that array.
# Anchor: line after the sources_phase files opening that contains ggml-backend.c

# Find the PBXSourcesBuildPhase and inject our new entries before the closing );
# Strategy: find the pattern "ggml-backend.c in Sources" inside the files list
# and insert our new entries before it

pbx_sources_anchor = '\t\t\tD59378D9034D4852AF46C8FD /* ggml-backend.c in Sources */,'
pbx_sources_inject = (
    f'\t\t\tD59378D9034D4852AF46C8FD /* ggml-backend.c in Sources */,\n'
    f'\t\t\t{ID_BF_METAL_M} /* ggml-metal.m in Sources */,\n'
    f'\t\t\t{ID_BF_METAL_MTL} /* ggml-metal.metal in Sources */,'
)
src = src.replace(pbx_sources_anchor, pbx_sources_inject, 1)
print("✓ Compile Sources phase updated")

# ── 4. Add Metal.framework to Frameworks phase ───────────────────────────────
fw_anchor = '\t\t\t\tEB01E5579F7A4BA6AB64A22E /* Sparkle in Frameworks */,'
fw_inject = (
    f'\t\t\t\t{ID_BF_METAL_FW} /* Metal.framework in Frameworks */,\n'
    f'\t\t\t\tEB01E5579F7A4BA6AB64A22E /* Sparkle in Frameworks */,'
)
src = src.replace(fw_anchor, fw_inject, 1)
print("✓ Frameworks phase updated")

# ── 5. Add compiler flags to Debug + Release configs ─────────────────────────
# Inject OTHER_CFLAGS and OTHER_CPLUSPLUSFLAGS right before OTHER_SWIFT_FLAGS
# Both configs have OTHER_SWIFT_FLAGS. We replace both occurrences.
FLAGS = (
    '\t\t\tOTHER_CFLAGS = "-DGGML_USE_METAL";\n'
    '\t\t\tOTHER_CPLUSPLUSFLAGS = "-DGGML_USE_METAL";\n'
    '\t\t\tOTHER_SWIFT_FLAGS ='
)
src = src.replace('\t\t\tOTHER_SWIFT_FLAGS =', FLAGS)
print("✓ OTHER_CFLAGS + OTHER_CPLUSPLUSFLAGS added to Debug and Release configs")

# ── Write ─────────────────────────────────────────────────────────────────────
with open(PBXPROJ, 'w', encoding='utf-8') as f:
    f.write(src)
print(f"\nproject.pbxproj written.")

# ── Verify round-trip parse ───────────────────────────────────────────────────
try:
    from pbxproj import XcodeProject
    p = XcodeProject.load(PBXPROJ)
    print("Parse validation: OK")
except Exception as e:
    print(f"Parse validation WARNING: {e}")

# ── Verify key strings are present ───────────────────────────────────────────
with open(PBXPROJ, 'r') as f:
    final = f.read()

checks = [
    ('ggml-metal.h file reference', 'ggml-metal.h'),
    ('ggml-metal.m file reference', 'ggml-metal.m'),
    ('ggml-metal.metal file reference', 'ggml-metal.metal'),
    ('Metal.framework reference', 'Metal.framework'),
    ('ggml-metal.m in Sources', f'{ID_BF_METAL_M} /* ggml-metal.m in Sources */'),
    ('ggml-metal.metal in Sources', f'{ID_BF_METAL_MTL} /* ggml-metal.metal in Sources */'),
    ('Metal.framework in Frameworks', f'{ID_BF_METAL_FW} /* Metal.framework in Frameworks */'),
    ('OTHER_CFLAGS set', 'OTHER_CFLAGS = "-DGGML_USE_METAL"'),
    ('OTHER_CPLUSPLUSFLAGS set', 'OTHER_CPLUSPLUSFLAGS = "-DGGML_USE_METAL"'),
]

all_ok = True
for label, needle in checks:
    if needle in final:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ MISSING: {label}")
        all_ok = False

if all_ok:
    print("\n✅ All checks passed. Next: clean build (⇧⌘K) + ⌘B in Xcode.")
else:
    print("\n⚠️  Some checks failed — review project.pbxproj manually.")
    sys.exit(1)
