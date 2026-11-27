import Foundation
#if canImport(Vision) && canImport(ImageIO)
import Vision
import ImageIO
#if canImport(CoreML)
import CoreML
#endif
#if os(macOS) && canImport(Metal)
import Metal
#endif
#endif

/// A line of text read from the screenshot. `box` is in parts of the picture (0 to 1, from the top
/// left), so it maps to screen points by multiplying with the screen size.
public struct RecognizedText: Sendable, Equatable {
    public var text: String
    public var box: Rect
    public init(text: String, box: Rect) {
        self.text = text
        self.box = box
    }
}

/// Text recognition on the phone (Vision). Nil where Vision is missing (Linux) or the picture cannot
/// be read.
enum TextRecognizer {
    #if os(macOS) && canImport(Metal)
    private static let prefersCPU: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return true }
        return device.name.localizedCaseInsensitiveContains("Paravirtual")
    }()
    #else
    private static let prefersCPU = false
    #endif

    static func recognize(png: Data, in region: Rect? = nil) -> [RecognizedText]? {
        #if canImport(Vision) && canImport(ImageIO)
        return recognize(png: png, in: region, preferCPU: prefersCPU, run: performVision)
        #else
        return nil
        #endif
    }

    /// Runs Vision off Swift Concurrency's cooperative thread pool so a slow or hung Vision call
    /// cannot starve deadlines or timers on small-core hosts.
    static func recognizeAsync(png: Data, in region: Rect? = nil) async -> [RecognizedText]? {
        #if canImport(Vision) && canImport(ImageIO)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: recognize(png: png, in: region))
            }
        }
        #else
        return nil
        #endif
    }

    #if canImport(Vision) && canImport(ImageIO)
    struct Attempt: Equatable {
        let level: VNRequestTextRecognitionLevel
        let detectLanguage: Bool
        let cpuOnly: Bool
    }

    static func attempts(for region: Rect?, preferCPU: Bool = prefersCPU) -> [Attempt] {
        let primaryLevel: VNRequestTextRecognitionLevel = region == nil ? .accurate : .fast
        let detectLanguage = region == nil
        var list = preferCPU
            ? [Attempt(level: primaryLevel, detectLanguage: detectLanguage, cpuOnly: true),
               Attempt(level: primaryLevel, detectLanguage: detectLanguage, cpuOnly: false)]
            : [Attempt(level: primaryLevel, detectLanguage: detectLanguage, cpuOnly: false),
               Attempt(level: primaryLevel, detectLanguage: detectLanguage, cpuOnly: true)]
        if region == nil {
            list.append(Attempt(level: .accurate, detectLanguage: false, cpuOnly: true))
            list.append(Attempt(level: .fast, detectLanguage: false, cpuOnly: true))
        }
        return list
    }

    static func recognize(
        png: Data,
        in region: Rect? = nil,
        preferCPU: Bool = prefersCPU,
        run: (CGImage, Attempt) throws -> [VNRecognizedTextObservation]
    ) -> [RecognizedText]? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let input: CGImage
        let area: Rect
        if let region {
            let width = Double(image.width), height = Double(image.height)
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let pixels = CGRect(x: region.x * width, y: region.y * height,
                                width: region.width * width, height: region.height * height).integral.intersection(bounds)
            guard !pixels.isEmpty, let crop = image.cropping(to: pixels) else { return nil }
            input = crop
            area = Rect(x: pixels.minX / width, y: pixels.minY / height,
                        width: pixels.width / width, height: pixels.height / height)
        } else {
            input = image
            area = Rect(x: 0, y: 0, width: 1, height: 1)
        }
        var observations: [VNRecognizedTextObservation]?
        for attempt in attempts(for: region, preferCPU: preferCPU) {
            if let results = try? run(input, attempt) {
                observations = results
                break
            }
        }
        guard let observations else { return nil }
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first, !best.string.isEmpty else { return nil }
            let b = observation.boundingBox
            let box = Rect(x: area.x + Double(b.minX) * area.width, y: area.y + Double(1 - b.maxY) * area.height,
                           width: Double(b.width) * area.width, height: Double(b.height) * area.height)
            return RecognizedText(text: best.string, box: box)
        }
    }

    static func performVision(_ input: CGImage, attempt: Attempt) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = attempt.level
        request.usesLanguageCorrection = false
        if #available(iOS 16, macOS 13, *), attempt.detectLanguage {
            request.automaticallyDetectsLanguage = true
        }
        if attempt.cpuOnly {
            #if canImport(CoreML)
            if let stages = try? request.supportedComputeStageDevices {
                for (stage, devices) in stages {
                    if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                        request.setComputeDevice(cpu, for: stage)
                    }
                }
            }
            #endif
        }
        try VNImageRequestHandler(cgImage: input, options: [:]).perform([request])
        return request.results ?? []
    }
    #endif
}

extension CoreHost {
    /// Vision on the phone; a host may answer differently (tests do).
    public func recognizeText(inPNG png: Data) async -> [RecognizedText]? { await TextRecognizer.recognizeAsync(png: png) }
    /// Nothing to prepare by default.
    public func warmUp() {}
}
