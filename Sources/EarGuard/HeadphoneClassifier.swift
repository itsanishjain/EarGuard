import Foundation
import CoreAudio

enum HeadphoneClassifier {
    private static let headphoneWords = [
        "headphone", "headphones", "earbud", "earbuds", "buds", "airpods",
        "headset", "earphone", "earphones", "arctis", "beats", "wh-",
        "wf-", "redmi", "galaxy buds", "nothing ear", "soundcore"
    ]

    private static let speakerWords = [
        "speaker", "speakers", "display", "monitor", "tv", "television",
        "soundbar", "homepod", "receiver", "hdmi", "airplay"
    ]

    static func isHeadphone(transportType: UInt32?, dataSource: UInt32?, name: String) -> Bool {
        let normalizedName = name.lowercased()

        if speakerWords.contains(where: { normalizedName.contains($0) }) {
            return false
        }

        if let transportType,
           transportType == kAudioDeviceTransportTypeBluetooth ||
           transportType == kAudioDeviceTransportTypeBluetoothLE {
            return true
        }

        if let transportType,
           transportType == kAudioDeviceTransportTypeBuiltIn,
           dataSource == FourCharCode("hdpn") {
            return true
        }

        if headphoneWords.contains(where: { normalizedName.contains($0) }) {
            return true
        }

        return false
    }
}

func FourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for scalar in string.utf8.prefix(4) {
        result = (result << 8) + UInt32(scalar)
    }
    return result
}

func fourCharString(_ code: UInt32?) -> String {
    guard let code else { return "n/a" }
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
}
