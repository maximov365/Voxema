// TODO: ONNX Runtime integration — manual setup required.
//
// ONNX Runtime is not available via Swift Package Manager.
// The Diarize stage (ECAPA-TDNN speaker embeddings) requires ONNX Runtime
// with CoreML Execution Provider for ANE/GPU delegation (DEC-2).
//
// Integration approach to be defined in the DIARIZE Architect plan.
// Steps required before the DIARIZE task begins:
//   1. Download the ONNX Runtime for Apple Silicon release from:
//      https://github.com/microsoft/onnxruntime/releases
//   2. Add OnnxRuntime.xcframework to Frameworks, Libraries, and Embedded Content
//      in the Voxema target.
//   3. Add a bridging header or Swift C interop wrapper in this module.
//   4. Embed the framework and set correct signing settings.
//
// Do not add any ONNX Runtime code here until the DIARIZE Architect plan
// defines the full integration contract.
