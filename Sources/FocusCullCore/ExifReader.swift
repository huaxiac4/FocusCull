import Foundation
import ImageIO

public struct ExifEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct ExifSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let entries: [ExifEntry]

    public init(id: String, title: String, entries: [ExifEntry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}

public struct ExifInfo: Sendable {
    public let sections: [ExifSection]
    public let plainText: String
    public let hasCameraMetadata: Bool

    public var isEmpty: Bool { sections.isEmpty }

    public init(sections: [ExifSection]) {
        self.sections = sections
        self.hasCameraMetadata = sections.contains { $0.id != "file" && !$0.entries.isEmpty }
        self.plainText = sections
            .map { section in
                "【\(section.title)】\n" + section.entries
                    .map { "\($0.label)：\($0.value)" }
                    .joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }
}

/// Reads all available ImageIO metadata, not just a hand-picked EXIF subset.
public enum ExifReader {
    public static func read(url: URL) -> ExifInfo {
        var sections: [ExifSection] = []
        let resourceValues = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let fileSize = Int64(resourceValues?.fileSize ?? 0)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return ExifInfo(sections: [])
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        let exif = properties?[kCGImagePropertyExifDictionary] as? NSDictionary
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? NSDictionary
        let gps = properties?[kCGImagePropertyGPSDictionary] as? NSDictionary
        let aux = properties?[kCGImagePropertyExifAuxDictionary] as? NSDictionary
        let iptc = properties?[kCGImagePropertyIPTCDictionary] as? NSDictionary

        var fileEntries: [ExifEntry] = [
            entry("file.name", "文件名", url.lastPathComponent),
            entry("file.format", "格式", url.pathExtension.uppercased())
        ]
        if fileSize > 0 {
            fileEntries.append(entry("file.size", "文件大小", formattedFileSize(fileSize)))
        }
        if let width = number(properties?[kCGImagePropertyPixelWidth]),
           let height = number(properties?[kCGImagePropertyPixelHeight]) {
            fileEntries.append(entry("file.dimensions", "像素尺寸", "\(Int(width)) × \(Int(height))"))
        }
        if let colorModel = properties?[kCGImagePropertyColorModel] as? String {
            fileEntries.append(entry("file.colorModel", "色彩模型", colorModel))
        }
        if let depth = number(properties?[kCGImagePropertyDepth]) {
            fileEntries.append(entry("file.depth", "位深", "\(Int(depth)) bit"))
        }
        if let orientation = number(properties?[kCGImagePropertyOrientation]) {
            fileEntries.append(entry("file.orientation", "方向", orientationText(Int(orientation))))
        }
        if let dpiWidth = number(properties?[kCGImagePropertyDPIWidth]),
           let dpiHeight = number(properties?[kCGImagePropertyDPIHeight]) {
            fileEntries.append(entry("file.dpi", "分辨率", "\(decimal(dpiWidth)) × \(decimal(dpiHeight)) DPI"))
        }
        if let profile = properties?[kCGImagePropertyProfileName] as? String, !profile.isEmpty {
            fileEntries.append(entry("file.profile", "色彩描述", profile))
        }
        if let modified = resourceValues?.contentModificationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            fileEntries.append(entry("file.modified", "文件修改时间", formatter.string(from: modified)))
        }
        sections.append(ExifSection(id: "file", title: "文件", entries: fileEntries))

        if let tiff {
            let entries = dictionaryEntries(tiff, sectionID: "tiff")
            if !entries.isEmpty {
                sections.append(ExifSection(id: "tiff", title: "相机与机身", entries: entries))
            }
        }

        if let exif {
            var entries = dictionaryEntries(exif, sectionID: "exif")
            entries.sort { lhs, rhs in
                let left = order(of: lhs.id)
                let right = order(of: rhs.id)
                if left != right { return left < right }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
            if !entries.isEmpty {
                sections.append(ExifSection(id: "exif", title: "拍摄参数", entries: entries))
            }
        }

        if let gps {
            var entries = dictionaryEntries(gps, sectionID: "gps")
            if let coordinate = coordinateText(latitude: gps["Latitude"], latitudeRef: gps["LatitudeRef"],
                                               longitude: gps["Longitude"], longitudeRef: gps["LongitudeRef"]) {
                entries.insert(entry("gps.coordinate", "坐标（十进制）", coordinate), at: 0)
            }
            if !entries.isEmpty {
                sections.append(ExifSection(id: "gps", title: "GPS", entries: entries))
            }
        }

        if let aux {
            let entries = dictionaryEntries(aux, sectionID: "aux")
            if !entries.isEmpty {
                sections.append(ExifSection(id: "aux", title: "镜头与辅助信息", entries: entries))
            }
        }

        if let iptc {
            let entries = dictionaryEntries(iptc, sectionID: "iptc")
            if !entries.isEmpty {
                sections.append(ExifSection(id: "iptc", title: "IPTC", entries: entries))
            }
        }

        let topLevel = otherTopLevelEntries(properties)
        if !topLevel.isEmpty {
            sections.append(ExifSection(id: "other", title: "其他", entries: topLevel))
        }

        return ExifInfo(sections: sections)
    }

    // MARK: - Dictionary conversion

    private static func dictionaryEntries(_ dictionary: NSDictionary, sectionID: String) -> [ExifEntry] {
        var result: [ExifEntry] = []
        for (key, value) in dictionary {
            guard let keyString = key as? String else { continue }
            result.append(entry(
                "\(sectionID).\(keyString)",
                label(for: keyString),
                formatted(key: keyString, value: value)
            ))
        }
        return result.sorted { lhs, rhs in
            let left = order(of: lhs.id)
            let right = order(of: rhs.id)
            if left != right { return left < right }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    private static func otherTopLevelEntries(_ properties: NSDictionary?) -> [ExifEntry] {
        guard let properties else { return [] }
        let handled: Set<String> = [
            kCGImagePropertyPixelWidth as String,
            kCGImagePropertyPixelHeight as String,
            kCGImagePropertyColorModel as String,
            kCGImagePropertyDepth as String,
            kCGImagePropertyOrientation as String,
            kCGImagePropertyDPIWidth as String,
            kCGImagePropertyDPIHeight as String,
            kCGImagePropertyProfileName as String,
            kCGImagePropertyExifDictionary as String,
            kCGImagePropertyTIFFDictionary as String,
            kCGImagePropertyGPSDictionary as String,
            kCGImagePropertyExifAuxDictionary as String,
            kCGImagePropertyIPTCDictionary as String
        ]
        var result: [ExifEntry] = []
        for (key, value) in properties {
            guard let keyString = key as? String, !handled.contains(keyString) else { continue }
            if let dictionary = value as? NSDictionary {
                for (nestedKey, nestedValue) in dictionary {
                    guard let nestedString = nestedKey as? String else { continue }
                    result.append(entry(
                        "other.\(keyString).\(nestedString)",
                        "\(keyString).\(nestedString)",
                        formatted(key: nestedString, value: nestedValue)
                    ))
                }
            } else {
                result.append(entry(
                    "other.\(keyString)",
                    label(for: keyString),
                    formatted(key: keyString, value: value)
                ))
            }
        }
        return result.sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    // MARK: - Labels

    private static let labels: [String: String] = [
        // File / TIFF
        "Make": "相机品牌",
        "Model": "相机型号",
        "Software": "软件",
        "Artist": "作者",
        "Copyright": "版权",
        "DateTime": "文件日期",
        "ImageDescription": "图像描述",
        "XResolution": "水平分辨率",
        "YResolution": "垂直分辨率",
        "ResolutionUnit": "分辨率单位",
        "Orientation": "方向",
        "HostComputer": "主机",
        // Exposure
        "ExposureTime": "快门速度",
        "FNumber": "光圈",
        "ExposureProgram": "曝光程序",
        "SpectralSensitivity": "光谱感光度",
        "ISOSpeedRatings": "ISO",
        "PhotographicSensitivity": "ISO",
        "SensitivityType": "感光度类型",
        "RecommendedExposureIndex": "推荐曝光指数",
        "ExifVersion": "EXIF 版本",
        "DateTimeOriginal": "拍摄时间",
        "DateTimeDigitized": "数字化时间",
        "OffsetTime": "时区偏移",
        "OffsetTimeOriginal": "拍摄时区",
        "OffsetTimeDigitized": "数字化时区",
        "ComponentsConfiguration": "色彩组件",
        "CompressedBitsPerPixel": "压缩位/像素",
        "ShutterSpeedValue": "快门速度值",
        "ApertureValue": "光圈值",
        "BrightnessValue": "亮度",
        "ExposureBiasValue": "曝光补偿",
        "MaxApertureValue": "最大光圈",
        "SubjectDistance": "主体距离",
        "MeteringMode": "测光模式",
        "LightSource": "光源",
        "Flash": "闪光灯",
        "FocalLength": "焦距",
        "SubjectArea": "主体区域",
        "MakerNote": "厂商注释",
        "UserComment": "用户注释",
        "SubsecTime": "秒以下",
        "SubsecTimeOriginal": "拍摄秒以下",
        "SubsecTimeDigitized": "数字化秒以下",
        "FlashpixVersion": "FlashPix 版本",
        "FlashPixVersion": "FlashPix 版本",
        "ColorSpace": "色彩空间",
        "PixelXDimension": "EXIF 像素宽",
        "PixelYDimension": "EXIF 像素高",
        "RelatedSoundFile": "相关声音文件",
        "InteroperabilityOffset": "互操作偏移",
        "FocalPlaneXResolution": "焦平面水平分辨率",
        "FocalPlaneYResolution": "焦平面垂直分辨率",
        "FocalPlaneResolutionUnit": "焦平面分辨率单位",
        "SensingMethod": "感光方式",
        "FileSource": "文件来源",
        "SceneType": "场景类型",
        "CFAPattern": "CFA 图案",
        "CustomRendered": "自定义渲染",
        "ExposureMode": "曝光模式",
        "WhiteBalance": "白平衡",
        "DigitalZoomRatio": "数码变焦",
        "FocalLengthIn35mmFilm": "35mm 等效焦距",
        "FocalLenIn35mmFilm": "35mm 等效焦距",
        "SceneCaptureType": "场景类型",
        "GainControl": "增益控制",
        "Contrast": "对比度",
        "Saturation": "饱和度",
        "Sharpness": "锐度",
        "SubjectDistanceRange": "主体距离范围",
        "SubjectDistRange": "主体距离范围",
        "ImageUniqueID": "图像唯一 ID",
        "CameraOwnerName": "相机所有者",
        "BodySerialNumber": "机身序列号",
        "LensSpecification": "镜头规格",
        "LensMake": "镜头品牌",
        "LensModel": "镜头型号",
        "LensSerialNumber": "镜头序列号",
        "LensInfo": "镜头信息",
        "LensID": "镜头 ID",
        "SerialNumber": "序列号",
        "OwnerName": "所有者",
        "Firmware": "固件",
        "ImageNumber": "图像编号",
        "FlashCompensation": "闪光补偿",
        // GPS
        "Latitude": "纬度",
        "LatitudeRef": "纬度参考",
        "Longitude": "经度",
        "LongitudeRef": "经度参考",
        "Altitude": "海拔",
        "AltitudeRef": "海拔参考",
        "TimeStamp": "GPS 时间",
        "Satellites": "卫星",
        "Status": "GPS 状态",
        "MeasureMode": "测量模式",
        "DOP": "精度因子",
        "Speed": "速度",
        "SpeedRef": "速度单位",
        "Track": "航向",
        "TrackRef": "航向参考",
        "ImgDirection": "图像方向",
        "ImgDirectionRef": "图像方向参考",
        "MapDatum": "地图基准",
        "DestLatitude": "目的地纬度",
        "DestLongitude": "目的地经度",
        "DestBearing": "目的地方位",
        "DestDistance": "目的地距离",
        "ProcessingMethod": "定位方式",
        "AreaInformation": "区域信息",
        "DateStamp": "GPS 日期",
        "Differential": "差分校正",
        "HPositioningError": "水平定位误差",
        // IPTC
        "Caption": "说明",
        "Keywords": "关键词",
        "City": "城市",
        "Country": "国家",
        "ProvinceState": "省/州",
        "Byline": "作者",
        "Credit": "署名",
        "Source": "来源",
        "ObjectName": "标题"
    ]

    private static func label(for key: String) -> String {
        labels[key] ?? key
    }

    private static func order(of id: String) -> Int {
        let key = id.split(separator: ".").dropFirst().joined(separator: ".")
        let ordered = [
            "Make", "Model", "LensMake", "LensModel", "LensSpecification", "LensSerialNumber",
            "BodySerialNumber", "SerialNumber", "Software", "DateTimeOriginal", "DateTimeDigitized",
            "ExposureTime", "FNumber", "ISOSpeedRatings", "PhotographicSensitivity", "ExposureProgram",
            "ExposureBiasValue", "MeteringMode", "Flash", "FocalLength", "FocalLengthIn35mmFilm",
            "WhiteBalance", "ColorSpace", "Orientation"
        ]
        return ordered.firstIndex(of: key) ?? 1000
    }

    // MARK: - Formatting

    private static func formatted(key: String, value: Any) -> String {
        if let numeric = number(value) {
            switch key {
            case "ExposureTime":
                return exposureTime(numeric)
            case "FNumber":
                return "f/\(decimal(numeric))"
            case "FocalLength":
                return "\(decimal(numeric)) mm"
            case "FocalLengthIn35mmFilm", "FocalLenIn35mmFilm":
                return "\(Int(numeric)) mm（等效）"
            case "ISOSpeedRatings", "PhotographicSensitivity":
                return "ISO \(Int(numeric))"
            case "ExposureBiasValue":
                return "\(signedDecimal(numeric)) EV"
            case "BrightnessValue":
                return "\(decimal(numeric)) EV"
            case "ShutterSpeedValue":
                return "\(decimal(numeric)) EV（约 \(exposureTime(pow(2, -numeric)))）"
            case "ApertureValue", "MaxApertureValue":
                let fNumber = pow(2, numeric / 2)
                return "\(decimal(numeric)) EV（f/\(decimal(fNumber))）"
            case "SubjectDistance":
                return "\(decimal(numeric)) m"
            case "DigitalZoomRatio":
                return "\(decimal(numeric))×"
            case "Orientation":
                return orientationText(Int(numeric))
            case "ResolutionUnit", "FocalPlaneResolutionUnit":
                return resolutionUnitText(Int(numeric))
            case "ExposureProgram":
                return exposureProgramText(Int(numeric))
            case "MeteringMode":
                return meteringText(Int(numeric))
            case "LightSource":
                return lightSourceText(Int(numeric))
            case "Flash":
                return flashText(Int(numeric))
            case "ColorSpace":
                return colorSpaceText(Int(numeric))
            case "WhiteBalance":
                return numeric == 0 ? "自动" : "手动"
            case "ExposureMode":
                return numeric == 0 ? "自动曝光" : (numeric == 1 ? "手动曝光" : "自动包围")
            case "CustomRendered":
                return numeric == 0 ? "正常" : "自定义"
            case "SceneCaptureType":
                return ["标准", "风景", "人像", "夜景"].indices.contains(Int(numeric))
                    ? ["标准", "风景", "人像", "夜景"][Int(numeric)] : "\(Int(numeric))"
            case "Contrast", "Saturation", "Sharpness":
                return numeric == 0 ? "标准" : (numeric == 1 ? "增强" : "柔和")
            case "GainControl":
                return ["无", "低增益", "高增益"][safe: Int(numeric)] ?? "\(Int(numeric))"
            case "SubjectDistanceRange":
                return ["未知", "微距", "近景", "远景"][safe: Int(numeric)] ?? "\(Int(numeric))"
            case "SensingMethod":
                return ["未定义", "单芯片色彩区域", "双芯片色彩区域", "三芯片色彩区域",
                        "色彩顺序区域", "线性", "彩色顺序线性"][safe: Int(numeric) - 1] ?? "\(Int(numeric))"
            case "FileSource":
                return numeric == 3 ? "数字相机" : "\(Int(numeric))"
            case "SceneType":
                return numeric == 1 ? "直接拍摄" : "\(Int(numeric))"
            case "GPSAltitude", "Altitude":
                return "\(decimal(numeric)) m"
            case "GPSAltitudeRef", "AltitudeRef":
                return numeric == 1 ? "海平面以下" : "海平面以上"
            case "GPSSpeed", "Speed":
                return "\(decimal(numeric))"
            case "GPSImgDirection", "GPSDestBearing", "ImgDirection", "DestBearing":
                return "\(decimal(numeric))°"
            case "GPSHPositioningError", "HPositioningError", "GPSDOP", "DOP":
                return decimal(numeric)
            case "ExposureIndex":
                return decimal(numeric)
            default:
                return rawValue(value)
            }
        }

        if let array = value as? [Any] {
            switch key {
            case "GPSLatitude", "GPSLongitude", "Latitude", "Longitude":
                if let degrees = coordinateDegrees(array) {
                    return "\(decimal(degrees))°"
                }
            case "ExifVersion", "FlashpixVersion", "FlashPixVersion":
                let components = array.compactMap { number($0).map { Int($0) } }
                if !components.isEmpty {
                    return components.map(String.init).joined(separator: ".")
                }
            case "GPSTimeStamp", "TimeStamp":
                if array.count >= 3, let h = number(array[0]), let m = number(array[1]), let s = number(array[2]) {
                    return String(format: "%02d:%02d:%02d", Int(h), Int(m), Int(s.rounded()))
                }
            case "LensSpecification":
                if array.count >= 4,
                   let minFocal = number(array[0]), let maxFocal = number(array[1]),
                   let minAperture = number(array[2]), let maxAperture = number(array[3]) {
                    let focal = minFocal == maxFocal
                        ? "\(decimal(minFocal)) mm"
                        : "\(decimal(minFocal))–\(decimal(maxFocal)) mm"
                    let aperture = minAperture == maxAperture
                        ? "f/\(decimal(minAperture))"
                        : "f/\(decimal(minAperture))–\(decimal(maxAperture))"
                    return "\(focal) · \(aperture)"
                }
            case "ComponentsConfiguration":
                let components = array.compactMap { number($0).map { Int($0) } }
                return components.map { ["", "Y", "Cb", "Cr", "R", "G", "B"][safe: $0] ?? "\($0)" }.joined()
            case "SubjectArea":
                return array.compactMap { number($0).map { decimal($0) } }.joined(separator: ", ")
            default:
                break
            }
            return array.map { rawValue($0) }.joined(separator: ", ")
        }

        if let data = value as? Data {
            switch key {
            case "ExifVersion", "FlashpixVersion", "FlashPixVersion":
                return String(data: data, encoding: .ascii) ?? "\(data.count) 字节"
            case "UserComment":
                return commentText(data)
            case "GPSProcessingMethod", "AreaInformation":
                let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8)
                return text?.trimmingCharacters(in: .controlCharacters.union(.whitespaces)) ?? "\(data.count) 字节"
            default:
                return "\(data.count) 字节"
            }
        }

        return rawValue(value)
    }

    private static func commentText(_ data: Data) -> String {
        var text: String?
        if data.count > 8 {
            let prefix = String(data: data.prefix(8), encoding: .ascii) ?? ""
            let body = data.dropFirst(8)
            if prefix.hasPrefix("ASCII") {
                text = String(data: body, encoding: .ascii)
            } else if prefix.hasPrefix("UNICODE") {
                text = String(data: body, encoding: .utf16)
            } else if prefix.hasPrefix("JIS") {
                text = String(data: body, encoding: .iso2022JP)
            }
        }
        if text == nil {
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        }
        return text?
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(data.count) 字节"
    }

    private static func exposureTime(_ value: Double) -> String {
        guard value > 0 else { return "0 秒" }
        if value >= 1 {
            return "\(decimal(value)) 秒"
        }
        let denominator = (1 / value).rounded()
        if denominator >= 2 {
            return "1/\(Int(denominator)) 秒"
        }
        return String(format: "%.4f 秒", value)
    }

    private static func coordinateValue(_ value: Any?) -> Double? {
        if let array = value as? [Any] {
            return coordinateDegrees(array)
        }
        return number(value)
    }

    private static func coordinateDegrees(_ array: [Any]) -> Double? {
        guard array.count >= 3,
              let degrees = number(array[0]),
              let minutes = number(array[1]),
              let seconds = number(array[2]) else {
            return nil
        }
        return degrees + minutes / 60 + seconds / 3600
    }

    private static func coordinateText(
        latitude: Any?,
        latitudeRef: Any?,
        longitude: Any?,
        longitudeRef: Any?
    ) -> String? {
        guard let lat = coordinateValue(latitude), let lon = coordinateValue(longitude) else {
            return nil
        }
        let latSuffix = (latitudeRef as? String) == "S" ? "S" : "N"
        let lonSuffix = (longitudeRef as? String) == "W" ? "W" : "E"
        return String(format: "%.6f° %@, %.6f° %@", lat, latSuffix, lon, lonSuffix)
    }

    private static func orientationText(_ value: Int) -> String {
        switch value {
        case 1: return "正常"
        case 2: return "水平翻转"
        case 3: return "旋转 180°"
        case 4: return "垂直翻转"
        case 5: return "转置"
        case 6: return "顺时针旋转 90°"
        case 7: return "横向转置"
        case 8: return "逆时针旋转 90°"
        default: return "\(value)"
        }
    }

    private static func resolutionUnitText(_ value: Int) -> String {
        switch value {
        case 2: return "英寸"
        case 3: return "厘米"
        default: return "\(value)"
        }
    }

    private static func exposureProgramText(_ value: Int) -> String {
        let names = [
            "未定义", "手动", "程序自动", "光圈优先", "快门优先",
            "创意程序", "运动程序", "人像模式", "风景模式"
        ]
        return names[safe: value] ?? "\(value)"
    }

    private static func meteringText(_ value: Int) -> String {
        switch value {
        case 0: return "未知"
        case 1: return "平均测光"
        case 2: return "中央重点平均"
        case 3: return "点测光"
        case 4: return "多点测光"
        case 5: return "矩阵测光"
        case 6: return "部分测光"
        case 255: return "其他"
        default: return "\(value)"
        }
    }

    private static func lightSourceText(_ value: Int) -> String {
        switch value {
        case 0: return "未知"
        case 1: return "日光"
        case 2: return "荧光灯"
        case 3: return "钨丝灯"
        case 4: return "闪光灯"
        case 9: return "晴天"
        case 10: return "阴天"
        case 11: return "阴影"
        default: return "\(value)"
        }
    }

    private static func flashText(_ value: Int) -> String {
        if value == 0 { return "未闪光" }
        var parts: [String] = []
        if value & 0x1 != 0 { parts.append("已闪光") }
        if value & 0x2 != 0 { parts.append("强制") }
        if value & 0x4 != 0 { parts.append("返回光") }
        if value & 0x8 != 0 { parts.append("自动") }
        if value & 0x10 != 0 { parts.append("未检测到返回光") }
        if value & 0x20 != 0 { parts.append("红眼") }
        return parts.isEmpty ? "\(value)" : parts.joined(separator: " · ")
    }

    private static func colorSpaceText(_ value: Int) -> String {
        switch value {
        case 1: return "sRGB"
        case 65535: return "未校准"
        default: return "\(value)"
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func decimal(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.000_001 {
            return String(Int(value.rounded()))
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func signedDecimal(_ value: Double) -> String {
        let text = decimal(value)
        return value > 0 ? "+\(text)" : text
    }

    private static func rawValue(_ value: Any) -> String {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return decimal(number.doubleValue)
        }
        if let array = value as? [Any] {
            return array.map { rawValue($0) }.joined(separator: ", ")
        }
        if let dictionary = value as? [String: Any] {
            return dictionary
                .map { "\($0.key)=\(rawValue($0.value))" }
                .sorted()
                .joined(separator: "; ")
        }
        if let data = value as? Data {
            return "\(data.count) 字节"
        }
        return String(describing: value)
    }

    private static func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func entry(_ id: String, _ label: String, _ value: String) -> ExifEntry {
        ExifEntry(id: id, label: label, value: value)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
