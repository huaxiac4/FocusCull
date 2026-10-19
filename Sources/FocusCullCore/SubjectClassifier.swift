import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum PhotoSubject: String, CaseIterable, Hashable, Sendable, Codable {
    case airplane
    case bird
    case animal
    case person
    case car
    case bicycle
    case motorcycle
    case other
    case unknown

    public var title: String {
        switch self {
        case .airplane: return "飞机"
        case .bird: return "鸟类"
        case .animal: return "动物"
        case .person: return "人物"
        case .car: return "汽车"
        case .bicycle: return "自行车"
        case .motorcycle: return "摩托车"
        case .other: return "其他"
        case .unknown: return "未识别"
        }
    }

    public var symbolName: String {
        switch self {
        case .airplane: return "airplane"
        case .bird: return "bird"
        case .animal: return "pawprint"
        case .person: return "person"
        case .car: return "car"
        case .bicycle: return "bicycle"
        case .motorcycle: return "motorcycle"
        case .other: return "square.grid.2x2"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct SubjectPrediction: Hashable, Sendable {
    public let subject: PhotoSubject
    public let confidence: Double
    public let identifier: String

    public init(subject: PhotoSubject, confidence: Double, identifier: String) {
        self.subject = subject
        self.confidence = confidence
        self.identifier = identifier
    }

    public var confidenceText: String {
        String(format: "%.0f%%", confidence * 100)
    }
}

public struct SubjectAnalysis: Sendable {
    public let prediction: SubjectPrediction
    /// A subject-aware focus region derived from faces / people / objects.
    public let focusRect: FocusRect?

    public init(prediction: SubjectPrediction, focusRect: FocusRect?) {
        self.prediction = prediction
        self.focusRect = focusRect
    }
}

/// Local subject analysis.
///
/// - Image classification, face detection, human detection, animal detection
///   and objectness saliency run through Vision, which uses the Apple Neural
///   Engine and GPU on Apple silicon.
/// - The result includes a subject-aware focus box: faces win for people, then
///   human bodies, animals, and salient objects, with the Metal-computed focus
///   region used to choose among competing object candidates.
public enum SubjectClassifier {
    public static func classify(url: URL) -> SubjectPrediction? {
        analyze(url: url, existingFocusRect: nil)?.prediction
    }

    public static func analyze(url: URL, existingFocusRect: FocusRect?) -> SubjectAnalysis? {
        guard let image = loadImage(url: url) else { return nil }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let classifyRequest = VNClassifyImageRequest()
        try? handler.perform([classifyRequest])
        var prediction = prediction(from: classifyRequest.results ?? [])
            ?? SubjectPrediction(subject: .unknown, confidence: 0, identifier: "")

        let faceRequest = VNDetectFaceRectanglesRequest()
        try? handler.perform([faceRequest])
        let faces = faceRequest.results ?? []

        let humanRequest = VNDetectHumanRectanglesRequest()
        try? handler.perform([humanRequest])
        let humans = humanRequest.results ?? []

        let animalRequest = VNRecognizeAnimalsRequest()
        try? handler.perform([animalRequest])
        let animals = animalRequest.results ?? []

        let objectRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? handler.perform([objectRequest])
        let objects = (objectRequest.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []

        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([attentionRequest])
        let attention = (attentionRequest.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []

        if !faces.isEmpty || !humans.isEmpty,
           prediction.subject == .unknown || prediction.subject == .other {
            let confidence = max(
                faces.map(\.confidence).max() ?? 0,
                humans.map(\.confidence).max() ?? 0
            )
            prediction = SubjectPrediction(
                subject: .person,
                confidence: Double(confidence),
                identifier: "person"
            )
        }

        let focus = chooseFocusRect(
            category: prediction.subject,
            faces: faces,
            humans: humans,
            animals: animals,
            objects: objects,
            attention: attention,
            existingFocusRect: existingFocusRect
        )
        return SubjectAnalysis(prediction: prediction, focusRect: focus)
    }

    // MARK: - Classification mapping

    private static func prediction(from observations: [VNClassificationObservation]) -> SubjectPrediction? {
        let sorted = observations.sorted { $0.confidence > $1.confidence }
        var specific: [(category: PhotoSubject, observation: VNClassificationObservation)] = []
        var personBest: VNClassificationObservation?
        var otherBest: VNClassificationObservation?
        let minimumConfidence: Float = 0.08

        for observation in sorted {
            guard observation.confidence >= minimumConfidence else { continue }
            let identifier = normalized(observation.identifier)
            if genericIdentifiers.contains(identifier) { continue }
            guard let category = category(for: observation.identifier) else {
                if otherBest == nil, observation.confidence >= 0.30 {
                    otherBest = observation
                }
                continue
            }
            if category == .person {
                if personBest == nil { personBest = observation }
            } else {
                specific.append((category, observation))
            }
        }

        // A specific object (airplane, bird, motorcycle, ...) should win over
        // a generic "people" label when the model also sees that object.
        let bestSpecific = specific.max { lhs, rhs in
            score(lhs, existing: nil) < score(rhs, existing: nil)
        }
        if let bestSpecific {
            let strongEnough = bestSpecific.observation.confidence >= 0.18
            let closeToPerson = personBest.map {
                bestSpecific.observation.confidence >= $0.confidence * 0.35
            } ?? true
            if strongEnough || closeToPerson {
                return SubjectPrediction(
                    subject: bestSpecific.category,
                    confidence: Double(bestSpecific.observation.confidence),
                    identifier: bestSpecific.observation.identifier
                )
            }
        }
        if let personBest {
            return SubjectPrediction(
                subject: .person,
                confidence: Double(personBest.confidence),
                identifier: personBest.identifier
            )
        }
        if let otherBest {
            return SubjectPrediction(
                subject: .other,
                confidence: Double(otherBest.confidence),
                identifier: otherBest.identifier
            )
        }
        return nil
    }

    private static func normalized(_ identifier: String) -> String {
        identifier
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func category(for identifier: String) -> PhotoSubject? {
        let text = normalized(identifier)

        if personKeywords.contains(where: { matches(text, $0) }) {
            return .person
        }
        if airplaneKeywords.contains(where: { matches(text, $0) }) {
            return .airplane
        }
        if motorcycleKeywords.contains(where: { matches(text, $0) }) {
            return .motorcycle
        }
        if bicycleKeywords.contains(where: { matches(text, $0) }) {
            return .bicycle
        }
        if birdKeywords.contains(where: { matches(text, $0) }) {
            return .bird
        }
        if carKeywords.contains(where: { matches(text, $0) }) {
            return .car
        }
        if animalKeywords.contains(where: { matches(text, $0) }) {
            return .animal
        }
        return nil
    }

    private static func matches(_ text: String, _ keyword: String) -> Bool {
        if keyword.contains(" ") {
            return text.contains(keyword)
        }
        if keyword.count > 4 {
            return text.contains(keyword)
        }
        return text.split(separator: " ").contains(Substring(keyword))
    }

    // MARK: - Subject-aware focus box

    private static func chooseFocusRect(
        category: PhotoSubject,
        faces: [VNFaceObservation],
        humans: [VNHumanObservation],
        animals: [VNRecognizedObjectObservation],
        objects: [VNRectangleObservation],
        attention: [VNRectangleObservation],
        existingFocusRect: FocusRect?
    ) -> FocusRect? {
        // A detected face is the strongest focus target for portraits. For a
        // vehicle/animal scene with a small rider/driver face, keep the
        // subject's Metal focus region instead of shrinking to that face.
        if let face = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) {
            let faceArea = Double(face.boundingBox.width * face.boundingBox.height)
            if category == .person || faceArea >= 0.045 {
                return expanded(visionRect(face.boundingBox), horizontal: 0.18, vertical: 0.24)
            }
        }

        if category == .person,
           let human = humans.max(by: {
               $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
           }) {
            return expanded(visionRect(human.boundingBox), horizontal: 0.07, vertical: 0.07)
        }

        if category == .animal {
            let recognized = animals.filter { observation in
                observation.labels.contains { label in
                    animalKeywords.contains(where: { matches(normalized(label.identifier), $0) })
                }
            }
            if let animal = recognized.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }) {
                return expanded(visionRect(animal.boundingBox), horizontal: 0.08, vertical: 0.08)
            }
        }

        // For images the classifier can only label as "other" (distant or
        // unusual subjects), use Vision's attention region. This is often the
        // only signal that finds a small aircraft against the sky.
        if (category == .other || existingFocusRect == nil),
           let attentionBox = attention.max(by: {
               $0.boundingBox.width * $0.boundingBox.height
                   < $1.boundingBox.width * $1.boundingBox.height
           }) {
            return expanded(visionRect(attentionBox.boundingBox), horizontal: 0.05, vertical: 0.05)
        }

        // The Metal focus-region pass is already a good general-purpose box
        // for aircraft, birds, cars and other subjects. Keep it unless Vision
        // found a face/person/animal/attention box above. Objectness is only a
        // fallback when no focus region was available.
        if let existingFocusRect {
            return existingFocusRect
        }

        let candidates = objects.filter { object in
            let area = Double(object.boundingBox.width * object.boundingBox.height)
            return object.confidence >= 0.12 && area > 0.002 && area < 0.92
        }
        guard !candidates.isEmpty else { return nil }
        let chosen = candidates.max { lhs, rhs in
            score(lhs, existing: nil) < score(rhs, existing: nil)
        }
        guard let chosen else { return nil }
        return expanded(visionRect(chosen.boundingBox), horizontal: 0.08, vertical: 0.08)
    }

    private static func score(
        _ candidate: (category: PhotoSubject, observation: VNClassificationObservation),
        existing: FocusRect?
    ) -> Double {
        let confidence = Double(candidate.observation.confidence)
        let preference = candidate.category == .motorcycle ? 0.04 : 0
        return confidence + preference
    }

    private static func score(_ object: VNRectangleObservation, existing: FocusRect?) -> Double {
        let rect = visionRect(object.boundingBox)
        let area = rect.width * rect.height
        let overlap = existing.map { intersectionOverUnion(rect, $0) } ?? 0
        return Double(object.confidence) * 1.4 + overlap * 2.6 + min(0.6, area * 3)
    }

    private static func visionRect(_ boundingBox: CGRect) -> FocusRect {
        FocusRect(
            x: Double(boundingBox.minX),
            y: Double(1 - boundingBox.maxY),
            width: Double(boundingBox.width),
            height: Double(boundingBox.height)
        )
    }

    private static func expanded(
        _ rect: FocusRect,
        horizontal: Double,
        vertical: Double
    ) -> FocusRect {
        let dx = rect.width * horizontal
        let dy = rect.height * vertical
        let x = max(0, rect.x - dx)
        let y = max(0, rect.y - dy)
        let maxX = min(1, rect.x + rect.width + dx)
        let maxY = min(1, rect.y + rect.height + dy)
        return FocusRect(
            x: x,
            y: y,
            width: max(0.001, maxX - x),
            height: max(0.001, maxY - y)
        )
    }

    private static func intersectionOverUnion(_ lhs: FocusRect, _ rhs: FocusRect) -> Double {
        let x1 = max(lhs.x, rhs.x)
        let y1 = max(lhs.y, rhs.y)
        let x2 = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let y2 = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersection = max(0, x2 - x1) * max(0, y2 - y1)
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersection
        return union > 0 ? intersection / union : 0
    }

    // MARK: - Image loading

    private static func loadImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        let maxPixel = 1024
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary), max(image.width, image.height) >= 480 {
            return image
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    // MARK: - Keyword sets

    private static let personKeywords = [
        "person", "people", "human", "man", "woman", "child", "baby",
        "face", "portrait", "bride", "groom", "athlete", "soldier",
        "dancer", "model", "selfie", "pedestrian"
    ]

    private static let airplaneKeywords = [
        "airplane", "aircraft", "airliner", "warplane", "plane", "jet",
        "bomber", "fighter", "helicopter", "glider", "seaplane", "biplane",
        "space shuttle", "rocket"
    ]

    private static let motorcycleKeywords = [
        "motorcycle", "motorbike", "motor scooter", "moped", "scooter", "harley"
    ]

    private static let bicycleKeywords = [
        "bicycle", "bike", "mountain bike", "tandem", "unicycle"
    ]

    private static let birdKeywords = [
        "bird", "eagle", "hawk", "kite", "vulture", "owl", "falcon",
        "osprey", "heron", "crane", "stork", "pelican", "albatross",
        "seagull", "gull", "duck", "goose", "swan", "parrot", "macaw",
        "cockatoo", "hummingbird", "kingfisher", "woodpecker", "finch",
        "sparrow", "robin", "warbler", "penguin", "ostrich", "flamingo",
        "peacock", "pigeon", "dove", "quail", "pheasant", "turkey",
        "bustard", "hoopoe", "hornbill", "toucan", "cuckoo", "nightjar",
        "swift", "swallow", "raven", "crow", "magpie", "jay", "chickadee",
        "nuthatch", "wren", "starling", "myna", "waterfowl", "shorebird",
        "raptor", "peregrine"
    ]

    private static let carKeywords = [
        "car", "automobile", "taxi", "jeep", "limousine", "minivan",
        "sports car", "convertible", "pickup", "truck", "bus", "van",
        "race car", "go kart", "tow truck", "fire engine", "ambulance"
    ]

    private static let animalKeywords = [
        "dog", "cat", "horse", "cow", "sheep", "goat", "pig", "elephant",
        "bear", "zebra", "giraffe", "deer", "fox", "wolf", "rabbit",
        "hare", "hamster", "guinea pig", "lion", "tiger", "leopard",
        "cheetah", "monkey", "ape", "gorilla", "chimpanzee", "panda",
        "koala", "kangaroo", "camel", "hippopotamus", "rhinoceros",
        "otter", "seal", "walrus", "dolphin", "whale", "shark", "fish",
        "turtle", "tortoise", "snake", "lizard", "crocodile", "alligator",
        "frog", "salamander", "spider", "insect", "butterfly", "dragonfly",
        "bee", "ant", "animal"
    ]

    private static let genericIdentifiers: Set<String> = [
        "animal", "vehicle", "machine", "object", "organism", "creature",
        "art", "decoration", "pattern", "material", "textile"
    ]
}
