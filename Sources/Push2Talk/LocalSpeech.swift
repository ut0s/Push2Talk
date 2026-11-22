import AVFoundation
import CryptoKit
import Foundation
import Push2TalkCore

enum SpeechEngine: String, CaseIterable {
  case system, whisper, qwen

  var title: String {
    switch self {
    case .system: return L10n.text("macOS 標準音声入力")
    case .whisper: return L10n.text("Whisper (MLX)（実験的）")
    case .qwen: return L10n.text("Qwen3-ASR（実験的）")
    }
  }

  var supported: Bool {
    if self == .system { return true }
    #if arch(arm64)
    if #available(macOS 14, *) { return true }
    #endif
    return false
  }

  var executableName: String? {
    switch self {
    case .system: return nil
    case .whisper: return "mlx_whisper"
    case .qwen: return "mlx-qwen3-asr"
    }
  }

  static let executableDirectories: [String] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let environment = ProcessInfo.processInfo.environment
    let paths = [
      environment["UV_TOOL_BIN_DIR"],
      home.appendingPathComponent(".local/bin").path,
      "/opt/homebrew/bin", "/usr/local/bin",
      home.appendingPathComponent(".cargo/bin").path,
    ].compactMap { $0 }
    return (paths + (environment["PATH"] ?? "").split(separator: ":").map(String.init))
      .filter { $0.hasPrefix("/") }
  }()

  static func locate(_ name: String) -> URL? {
    executableDirectories.lazy.map {
      URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(name)
    }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  var executable: URL? {
    guard let executableName, supported else { return nil }
    if self == .whisper && Self.locate("ffmpeg") == nil { return nil }
    return Self.locate(executableName)
  }
}

enum SpeechModel: String, CaseIterable {
  case base, small, qwen06, qwen17MLX, qwen17HF

  var isSelectable: Bool { self != .qwen17HF }

  var title: String {
    switch self {
    case .base: return "Whisper base · 144 MB"
    case .small: return "Whisper small · 481 MB"
    case .qwen06: return "Qwen3-ASR 0.6B · 542 MB"
    case .qwen17MLX: return "Qwen3-ASR 1.7B (MLX) · 1.31 GB"
    case .qwen17HF: return "Qwen3-ASR 1.7B-hf · 4.09 GB"
    }
  }

  var engine: SpeechEngine {
    switch self {
    case .base, .small: return .whisper
    case .qwen06, .qwen17MLX, .qwen17HF: return .qwen
    }
  }

  var executable: URL? {
    guard engine.supported else { return nil }
    guard self == .qwen17HF else { return engine.executable }
    // uv installs the Transformers CLI next to the Python interpreter in its tool environment.
    let python = SpeechEngine.locate("transformers")?.resolvingSymlinksInPath()
      .deletingLastPathComponent().appendingPathComponent("python")
    guard let python, FileManager.default.isExecutableFile(atPath: python.path) else { return nil }
    return python
  }

  var files: [(name: String, size: Int, sha256: String?)] {
    switch self {
    case .base:
      return [("config.json", 262, nil),
              ("weights.npz", 143_724_204, "2f57d5f3ef473054c638961f90716f4ee415e8108de81313eccb2c5fd62eff0b")]
    case .small:
      return [("config.json", 266, nil),
              ("weights.npz", 481_307_592, "55b6674c9b339702d486e2b1573839a66f8ec8f821ed2886993ef717a86b09f5")]
    case .qwen06:
      return [("config.json", 6193, nil), ("merges.txt", 1_671_853, nil), ("quantization_config.json", 60, nil),
              ("tokenizer_config.json", 12_487, nil), ("vocab.json", 2_776_833, nil),
              ("weights.safetensors", 537_626_967, "9a62bb9830dcbcd0cf1c1f40200161d4e5f007a4cd99b83111902890a9f087d3")]
    case .qwen17MLX:
      return [("config.json", 6194, nil), ("merges.txt", 1_671_853, nil), ("quantization_config.json", 60, nil),
              ("tokenizer_config.json", 12_487, nil), ("vocab.json", 2_776_833, nil),
              ("weights.safetensors", 1_309_676_755, "5c9177b6fc67851d3c1af234ab8bd9d240faf07d08499bf3e751257d1ec88c5f")]
    case .qwen17HF:
      return [("chat_template.jinja", 1434, nil), ("config.json", 2399, nil), ("generation_config.json", 165, nil),
              ("processor_config.json", 487, nil), ("tokenizer_config.json", 998, nil),
              ("tokenizer.json", 11_429_653, "fe1fad59be22a41ee293363fcf95fdedbc7c93f3b49270b1d2e18bd1399a7a05"),
              ("model.safetensors", 4_076_193_080, "2db53c7d81bd9b8cbc6a074e89be2c968a0d373fb4ee68bb1b1e14f7042dfee1")]
    }
  }

  var directory: URL {
    URL.applicationSupportDirectory.appendingPathComponent("Push2Talk/Models/\(rawValue)", isDirectory: true)
  }

  var installed: Bool {
    files.allSatisfy { name, size, _ in
      let values = try? directory.appendingPathComponent(name)
        .resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      return values?.isRegularFile == true && values?.fileSize == size
    }
  }

  var source: URL {
    let location: String
    switch self {
    case .base: location = "mlx-community/whisper-base-mlx/resolve/1e3e249fb8d01c655324bd6841b1deadffd6d04c"
    case .small: location = "mlx-community/whisper-small-mlx/resolve/45f3915923c7a79a5a5b5a7d909d39aeb0e5630e"
    case .qwen06: location = "moona3k/mlx-qwen3-asr-0.6b-4bit/resolve/4c59c533f95c84afb796655e814709034f826f04"
    case .qwen17MLX: location = "moona3k/mlx-qwen3-asr-1.7b-4bit/resolve/b2315a2537123353af98e37fc93eae078f1b7cf3"
    case .qwen17HF: location = "Qwen/Qwen3-ASR-1.7B-hf/resolve/bcd2b5b7f32b480ab5790554cfa8347f246a14f3"
    }
    return URL(string: "https://huggingface.co/\(location)/")!
  }
}

enum LocalSpeechError: Error {
  case downloadFailed, couldNotRecord, recognitionFailed
}

enum SpeechModelStore {
  static func download(_ model: SpeechModel) async throws {
    let manager = FileManager.default
    let staging = model.directory.deletingLastPathComponent()
      .appendingPathComponent(".\(model.rawValue).download", isDirectory: true)
    if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: staging) }
    for (file, size, sha256) in model.files {
      let (temporary, response) = try await URLSession.shared.download(from: model.source.appendingPathComponent(file))
      defer { try? manager.removeItem(at: temporary) }
      let actualSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
      guard (response as? HTTPURLResponse)?.statusCode == 200, actualSize == size else {
        throw LocalSpeechError.downloadFailed
      }
      if let sha256 {
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
          try Task.checkCancellation()
          hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw LocalSpeechError.downloadFailed }
      }
      try manager.moveItem(at: temporary, to: staging.appendingPathComponent(file))
    }
    if manager.fileExists(atPath: model.directory.path) {
      _ = try manager.replaceItemAt(model.directory, withItemAt: staging)
    } else {
      try manager.moveItem(at: staging, to: model.directory)
    }
  }
}

final class LocalSpeech {
  private let directory: URL
  private let model: SpeechModel
  private let executable: URL
  private var recorder: AVAudioRecorder?
  private var process: Process?
  private var timeout: DispatchWorkItem?

  init(model: SpeechModel, executable: URL) throws {
    self.model = model
    self.executable = executable
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("Push2Talk-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  }

  private var audio: URL { directory.appendingPathComponent("speech.wav") }

  func start() throws {
    let recorder = try AVAudioRecorder(url: audio, settings: [
      AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ])
    recorder.isMeteringEnabled = true
    guard recorder.record() else { throw LocalSpeechError.couldNotRecord }
    self.recorder = recorder
  }

  func recordingLevel() -> CGFloat? {
    guard let recorder, recorder.isRecording else { return nil }
    recorder.updateMeters()
    let decibels = CGFloat(recorder.averagePower(forChannel: 0))
    return min(1, max(0, (decibels + 45) / 45))
  }

  func transcribe(completion: @escaping (Result<String, Error>) -> Void) throws {
    recorder?.stop()
    recorder = nil
    let output = directory.appendingPathComponent("speech.txt")
    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = directory
    switch model {
    case .base, .small:
      process.arguments = [audio.path, "--model", model.directory.path, "--output-dir", directory.path,
                           "--output-format", "txt", "--verbose", "False", "--condition-on-previous-text", "False"]
    case .qwen06, .qwen17MLX:
      process.arguments = [audio.path, "--model", model.directory.path, "-f", "txt", "-o", directory.path, "--quiet"]
    case .qwen17HF:
      process.arguments = ["-c", Self.qwenTransformersScript, model.directory.path, audio.path, output.path]
    }
    var environment = ProcessInfo.processInfo.environment
    environment["HF_HUB_OFFLINE"] = "1"
    environment["VLLM_NO_USAGE_STATS"] = "1"
    environment["PATH"] = SpeechEngine.executableDirectories.joined(separator: ":")
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [self] finished in
      let result = Result {
        guard finished.terminationStatus == 0 else { throw LocalSpeechError.recognitionFailed }
        return try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      try? FileManager.default.removeItem(at: directory)
      DispatchQueue.main.async { [self] in
        timeout?.cancel()
        timeout = nil
        self.process = nil
        completion(result)
      }
    }
    do {
      try process.run()
    } catch {
      process.terminationHandler = nil
      throw error
    }
    self.process = process
    let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
  }

  private static let qwenTransformersScript = """
    import sys
    import wave
    from pathlib import Path

    import numpy as np
    import torch
    from transformers import AutoModelForMultimodalLM, AutoProcessor

    model_path, audio_path, output_path = sys.argv[1:]
    with wave.open(audio_path, "rb") as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
            raise ValueError("Expected mono 16-bit PCM at 16 kHz")
        samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2").astype(np.float32) / 32768

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    processor = AutoProcessor.from_pretrained(model_path, local_files_only=True)
    model = AutoModelForMultimodalLM.from_pretrained(
        model_path, local_files_only=True, dtype=torch.bfloat16, attn_implementation="eager"
    ).to(device).eval()
    inputs = processor.apply_transcription_request(
        audio=samples, return_tensors="pt"
    ).to(device, model.dtype)

    with torch.inference_mode():
        output = model.generate(**inputs, max_new_tokens=1024, do_sample=False)
    generated = output[:, inputs["input_ids"].shape[1]:]
    text = processor.decode(generated, return_format="transcription_only")[0]
    Path(output_path).write_text(text, encoding="utf-8")
    """

  func cancel() {
    recorder?.stop()
    recorder = nil
    timeout?.cancel()
    timeout = nil
    if let process {
      if process.isRunning { process.terminate() }
    } else {
      try? FileManager.default.removeItem(at: directory)
    }
  }
}
