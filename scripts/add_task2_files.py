#!/usr/bin/env python3
"""
Add TASK-2 new Swift files to Voxema.xcodeproj Xcode target.
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
TARGET = 'Voxema'

project = XcodeProject.load(PROJECT_PATH)

NEW_SOURCE_FILES = [
    'Voxema/Core/Models/AudioChannel.swift',
    'Voxema/Core/Models/AudioStream.swift',
    'Voxema/Core/Models/TranscribedSegment.swift',
    'Voxema/Core/Models/DiarizedSegment.swift',
    'Voxema/Core/Models/SpeakerIdentity.swift',
    'Voxema/Core/Models/MeetingSummary.swift',
    'Voxema/Core/Models/ActionItem.swift',
    'Voxema/Core/Models/Meeting.swift',
    'Voxema/Core/Models/MeetingMetadata.swift',
    'Voxema/Core/Models/PipelineError.swift',
]

NEW_TEST_FILES = [
    'VoxemaTests/CoreTests/DataTypesTests.swift',
]

def add_files(file_list, target_name):
    added = 0
    for rel_path in file_list:
        abs_path = os.path.join(ROOT, rel_path)
        if not os.path.exists(abs_path):
            print(f"  SKIP (not found): {rel_path}")
            continue
        try:
            project.add_file(abs_path, target_name=target_name, tree=TreeType.SOURCE_ROOT)
            print(f"  + {rel_path}")
            added += 1
        except Exception as e:
            print(f"  ~ skip {rel_path}: {e}")
    return added

print(f"Adding source files to target '{TARGET}'...")
n = add_files(NEW_SOURCE_FILES, TARGET)

print(f"\nAdding test files to target 'VoxemaTests'...")
# Check if VoxemaTests target exists
test_targets = [t for t in project.objects.get_targets('VoxemaTests')]
if test_targets:
    n2 = add_files(NEW_TEST_FILES, 'VoxemaTests')
else:
    print("  VoxemaTests target not found in xcodeproj — skipping test file wiring")
    n2 = 0

project.save()
print(f"\nSaved. {n} source files + {n2} test files added.")
