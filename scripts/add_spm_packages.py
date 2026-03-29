#!/usr/bin/env python3
"""
Add GRDB and Sparkle as XCRemoteSwiftPackageReference to Voxema.xcodeproj.
Versions from Package.resolved: GRDB 6.29.3, Sparkle 2.9.0
"""

import re
import sys
import os
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, 'Voxema.xcodeproj', 'project.pbxproj')

data = open(PBXPROJ).read()

# Check if already added
if 'XCRemoteSwiftPackageReference' in data:
    print("SPM packages already present in project. Skipping.")
    sys.exit(0)

def new_id():
    return uuid.uuid4().hex[:24].upper()

# IDs for GRDB
GRDB_PKG_ID     = new_id()
GRDB_DEP_ID     = new_id()
GRDB_BUILD_ID   = new_id()

# IDs for Sparkle
SPK_PKG_ID      = new_id()
SPK_DEP_ID      = new_id()
SPK_BUILD_ID    = new_id()

print(f"GRDB package ref: {GRDB_PKG_ID}")
print(f"GRDB product dep: {GRDB_DEP_ID}")
print(f"Sparkle package ref: {SPK_PKG_ID}")
print(f"Sparkle product dep: {SPK_DEP_ID}")

# ── 1. Add XCRemoteSwiftPackageReference section ──────────────────────────
spm_refs = f"""
/* Begin XCRemoteSwiftPackageReference section */
\t\t{GRDB_PKG_ID} /* XCRemoteSwiftPackageReference "GRDB.swift" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trequirementKind = upToNextMajorVersion;
\t\t\trequirementMinimumVersion = 6.0.0;
\t\t\trepositoryURL = "https://github.com/groue/GRDB.swift";
\t\t}};
\t\t{SPK_PKG_ID} /* XCRemoteSwiftPackageReference "Sparkle" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trequirementKind = upToNextMajorVersion;
\t\t\trequirementMinimumVersion = 2.0.0;
\t\t\trepositoryURL = "https://github.com/sparkle-project/Sparkle";
\t\t}};
/* End XCRemoteSwiftPackageReference section */
"""

# ── 2. Add XCSwiftPackageProductDependency section ────────────────────────
spm_deps = f"""
/* Begin XCSwiftPackageProductDependency section */
\t\t{GRDB_DEP_ID} /* GRDB */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {GRDB_PKG_ID} /* XCRemoteSwiftPackageReference "GRDB.swift" */;
\t\t\tproductName = GRDB;
\t\t}};
\t\t{SPK_DEP_ID} /* Sparkle */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {SPK_PKG_ID} /* XCRemoteSwiftPackageReference "Sparkle" */;
\t\t\tproductName = Sparkle;
\t\t}};
/* End XCSwiftPackageProductDependency section */
"""

# ── 3. Add PBXBuildFile entries for the products ──────────────────────────
build_files = f"""\t\t{GRDB_BUILD_ID} /* GRDB in Frameworks */ = {{isa = PBXBuildFile; productRef = {GRDB_DEP_ID} /* GRDB */; }};
\t\t{SPK_BUILD_ID} /* Sparkle in Frameworks */ = {{isa = PBXBuildFile; productRef = {SPK_DEP_ID} /* Sparkle */; }};
"""

# Insert build files before first existing build file entry
data = re.sub(
    r'(/\* Begin PBXBuildFile section \*/\n)',
    r'\1' + build_files,
    data
)

# ── 4. Add SPM references to project's packageReferences list ─────────────
# Find the PBXProject object and add packageReferences
if 'packageReferences' not in data:
    data = re.sub(
        r'(isa = PBXProject;)',
        f'isa = PBXProject;\n\t\t\tpackageReferences = (\n\t\t\t\t{GRDB_PKG_ID} /* XCRemoteSwiftPackageReference "GRDB.swift" */,\n\t\t\t\t{SPK_PKG_ID} /* XCRemoteSwiftPackageReference "Sparkle" */,\n\t\t\t);',
        data,
        count=1
    )
    print("Added packageReferences to PBXProject")

# ── 5. Add PBXFrameworksBuildPhase files ──────────────────────────────────
# Find PBXFrameworksBuildPhase for Voxema target and add our framework entries
data = re.sub(
    r'(isa = PBXFrameworksBuildPhase;[^}]*files = \()',
    r'\1\n\t\t\t\t' + GRDB_BUILD_ID + r' /* GRDB in Frameworks */,\n\t\t\t\t' + SPK_BUILD_ID + r' /* Sparkle in Frameworks */,',
    data,
    count=1
)
print("Added Frameworks to PBXFrameworksBuildPhase")

# ── 6. Add packageProductDependencies to target ───────────────────────────
# Find PBXNativeTarget and add packageProductDependencies
if 'packageProductDependencies' not in data:
    data = re.sub(
        r'(isa = PBXNativeTarget;)',
        f'isa = PBXNativeTarget;\n\t\t\tpackageProductDependencies = (\n\t\t\t\t{GRDB_DEP_ID} /* GRDB */,\n\t\t\t\t{SPK_DEP_ID} /* Sparkle */,\n\t\t\t);',
        data,
        count=1
    )
    print("Added packageProductDependencies to PBXNativeTarget")

# ── 7. Insert new sections before the closing brace of objects ────────────
data = re.sub(
    r'(/\* End XCConfigurationList section \*/)',
    spm_refs + spm_deps + r'\1',
    data
)

# ── 8. Save ────────────────────────────────────────────────────────────────
with open(PBXPROJ, 'w') as f:
    f.write(data)

print(f"\nSaved. GRDB and Sparkle added as SPM package dependencies.")
