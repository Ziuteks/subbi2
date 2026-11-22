import AVFoundation

/// Składa animację startową z wideo (`splash.mp4`) i dźwięku (`audio.m4a`) w jedną kompozycję,
/// odtwarzaną jednym `AVPlayer` – dźwięk i obraz są wtedy zawsze zsynchronizowane.
nonisolated enum SplashMedia {
    static func makeAsset(video videoURL: URL, audio audioURL: URL?) async throws -> AVAsset {
        let video = AVURLAsset(url: videoURL)
        guard let audioURL else { return video }
        let audio = AVURLAsset(url: audioURL)

        guard let videoTrack = try await video.loadTracks(withMediaType: .video).first else { return video }
        guard let audioTrack = try await audio.loadTracks(withMediaType: .audio).first else {
            log("w \(audioURL.lastPathComponent) nie ma ścieżki dźwiękowej")
            return video
        }
        let videoRange = try await videoTrack.load(.timeRange)
        let audioRange = try await audioTrack.load(.timeRange)
        let transform = try await videoTrack.load(.preferredTransform)
        let frame = try await videoTrack.load(.minFrameDuration)

        let composition = AVMutableComposition()
        guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return video }
        try v.insertTimeRange(videoRange, of: videoTrack, at: .zero)
        v.preferredTransform = transform
        try a.insertTimeRange(audioRange, of: audioTrack, at: .zero)

        // Dźwięk dłuższy od wideo: ostatnia klatka trwa do końca dźwięku, żeby logo nie zniknęło przed przejściem.
        let extra = audioRange.duration - videoRange.duration
        if extra > .zero, frame.isValid, frame > .zero {
            let last = CMTimeRange(start: videoRange.duration - frame, duration: frame)
            v.scaleTimeRange(last, toDuration: frame + extra)
        }
        log(String(format: "kompozycja: wideo %.2f s, dźwięk %.2f s", videoRange.duration.seconds, audioRange.duration.seconds))
        return composition
    }

    static func log(_ message: String) {
        #if DEBUG
        print("[Splash] \(message)")
        #endif
    }
}
