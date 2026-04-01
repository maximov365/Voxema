#!/usr/bin/env python3
"""
scripts/convert_ecapa_coreml.py  —  TASK-29 one-time developer step

Converts SpeechBrain ECAPA-TDNN (spkrec-ecapa-voxceleb) to a CoreML
.mlpackage that Voxema uses for on-device speaker diarization (DEC-16 Phase 2).

Prerequisites (developer machine only — not needed at runtime):
    pip install speechbrain torch torchaudio coremltools

Usage:
    python3 scripts/convert_ecapa_coreml.py

Output:
    ecapa-tdnn.mlpackage   (in the current directory)

Then copy into the project:
    mv ecapa-tdnn.mlpackage Voxema/Resources/Models/

And re-run the pbxproj script to bundle the package if it wasn't already added:
    python3 scripts/add_coreml_ecapa.py

Model contract (matches voxema_ecapa_coreml.m):
    Input  "waveform"  — float32 [1, N_samples], 16 kHz mono PCM, N in [1600, 480000]
    Output "embedding" — float32 [1, 192], L2-normalised speaker embedding
"""

import sys
import os

def check_deps():
    missing = []
    for pkg in ("torch", "torchaudio", "speechbrain", "coremltools"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(f"Missing dependencies: {', '.join(missing)}")
        print(f"Run: pip install {' '.join(missing)}")
        sys.exit(1)

check_deps()

import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct


class EcapaPipeline(nn.Module):
    """
    Wraps SpeechBrain ECAPA-TDNN with its FBANK feature extractor so that
    CoreML receives raw 16 kHz PCM and returns the L2-normalised embedding.

    Including FBANK in the trace means the C bridge (voxema_ecapa_coreml.m)
    does not need to implement feature extraction, keeping it simple.
    """

    def __init__(self, clf):
        super().__init__()
        self.compute_features = clf.mods.compute_features   # log-Mel FBANK
        self.embedding_model  = clf.mods.embedding_model    # ECAPA-TDNN encoder

    def forward(self, waveform: torch.Tensor) -> torch.Tensor:
        # waveform: [1, N_samples]
        feats = self.compute_features(waveform)             # [1, T_frames, 80]
        emb   = self.embedding_model(feats).squeeze(1)      # [1, 192] (squeeze time dim)
        return F.normalize(emb, p=2, dim=-1)                # L2-normalise


def main():
    from speechbrain.inference.classifiers import EncoderClassifier

    cache_dir = os.path.expanduser("~/.cache/voxema/ecapa_cache")
    print(f"Loading SpeechBrain ECAPA-TDNN (cache: {cache_dir}) ...")
    print("First run downloads ~80 MB of model weights from HuggingFace.")

    clf = EncoderClassifier.from_hparams(
        source="speechbrain/spkrec-ecapa-voxceleb",
        savedir=cache_dir,
        run_opts={"device": "cpu"},
    )
    clf.eval()

    pipeline = EcapaPipeline(clf).eval()

    # Use 2-second silence for tracing — FBANK needs > 25 ms (400 samples)
    example_waveform = torch.zeros(1, 32000)  # 2 s at 16 kHz

    print("Tracing model with torch.jit.trace ...")
    with torch.no_grad():
        traced = torch.jit.trace(pipeline, example_waveform, strict=False)

    # Verify trace output shape
    with torch.no_grad():
        test_out = traced(example_waveform)
    assert test_out.shape[-1] == 192, f"Unexpected output shape: {test_out.shape}"
    print(f"  Trace OK — output shape: {test_out.shape}")

    print("Converting to CoreML (this may take 1–2 minutes) ...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="waveform",
                shape=ct.Shape(shape=[1, ct.RangeDim(1600, 480000)]),  # 0.1 s – 30 s
                dtype=float,
            )
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=float)
        ],
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
    )

    output_path = "ecapa-tdnn.mlpackage"
    mlmodel.save(output_path)
    size_mb = sum(
        os.path.getsize(os.path.join(dirpath, f))
        for dirpath, _, files in os.walk(output_path)
        for f in files
    ) / 1_048_576

    print(f"\n✓ Saved: {output_path}  ({size_mb:.1f} MB)")
    print()
    print("Next steps:")
    print(f"  1. mv {output_path} Voxema/Resources/Models/")
    print(f"  2. python3 scripts/add_coreml_ecapa.py   (adds model to Xcode bundle)")
    print(f"  3. Build and run in Xcode.")
    print()
    print("Without the model file Voxema silently falls back to MFCC diarization.")


if __name__ == "__main__":
    main()
