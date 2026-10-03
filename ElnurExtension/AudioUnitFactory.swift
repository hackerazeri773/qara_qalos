import CoreAudioKit

/// Sistem eklentiyi yuklediginde Audio Unit ornegini bu sinif olusturur.
public class AudioUnitFactory: NSObject, AUAudioUnitFactory {

    var audioUnit: AUAudioUnit?

    public func beginRequest(with context: NSExtensionContext) {}

    @objc
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try ElnurAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        return unit
    }
}
