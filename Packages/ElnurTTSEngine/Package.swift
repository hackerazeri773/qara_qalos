// swift-tools-version: 5.9
// ElnurTTS motoru (RHVoice tabanli, GPL). Android surumuyle (Android.mk) ayni
// derleme ayarlari; ek olarak yuksek konusma hizlari icin Sonic acik.
import PackageDescription

let headerPaths = [
    "include",
    "private_include",
    "private_include/core",
    "private_include/utf8dir",
    "private_include/rapidxmldir",
    "hts_engine",
    "mage",
    "sonic",
]

let defines: [(String, String?)] = [
    // Android.mk ile ayni ayarlar. ELNURTTS olmadan MAGE perde verisini yanlis okur.
    ("ELNURTTS", nil),
    ("PACKAGE", "\"ElnurTTS\""),
    ("HTS_EMBEDDED", nil),
    ("HTS106_EMBEDDED", nil),
    ("MAX_VOLUME", "MAX_MAX_VOLUME"),
    ("DEFAULT_PUNCTUATION_MODE", "ElnurTTS_punctuation_some"),
    // iPhone farki: Sonic acik, en yuksek hiz 5 kat (Android: Sonic kapali, 3 kat)
    ("ENABLE_SONIC", "1"),
    ("MAX_RATE", "5"),
    ("_LIBCPP_ENABLE_CXX17_REMOVED_UNARY_BINARY_FUNCTION", nil),
]

let cSettings: [CSetting] =
    headerPaths.map { .headerSearchPath($0) } +
    defines.map { .define($0.0, to: $0.1) } +
    [.unsafeFlags(["-w"])]

let cxxSettings: [CXXSetting] =
    headerPaths.map { .headerSearchPath($0) } +
    defines.map { .define($0.0, to: $0.1) } +
    [.unsafeFlags(["-w"])]

let package = Package(
    name: "ElnurTTSEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ElnurTTSEngine", targets: ["ElnurTTSEngine"])],
    targets: [
        .target(
            name: "ElnurTTSEngine",
            path: "Sources/ElnurTTSEngine",
            exclude: [
                // Bu dosyalar baska dosyalarin icine #include ediliyor
                "core/unidata.cpp",
                "core/emoji_data.cpp",
                "core/userdict_parser.c",
                "core/userdict_parser.g",
                "private_include",
            ],
            sources: ["core", "lib", "hts_engine", "mage", "sonic"],
            publicHeadersPath: "include",
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            linkerSettings: [.linkedLibrary("c++")]
        )
    ],
    cLanguageStandard: .gnu11,
    cxxLanguageStandard: .gnucxx14
)
