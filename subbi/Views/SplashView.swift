import AVFoundation
import SwiftUI

/// Animacja startowa: wideo `Splash/splash.mp4` (logo przylatuje na środek) z dźwiękiem
/// `Splash/audio.m4a`, odtwarzane raz przy uruchomieniu (zob. `SplashMedia`).
/// Pierwsza klatka ma kolor tła ekranu startowego (LaunchBackground), więc przejście jest płynne.
/// Dotknięcie pomija animację; przy „Ogranicz ruch” nie jest odtwarzana.
struct SplashView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var videoURL: URL? {
        reduceMotion ? nil : Bundle.main.url(forResource: "splash", withExtension: "mp4")
    }

    var body: some View {
        ZStack {
            Theme.bg
            if let videoURL {
                SplashPlayer(video: videoURL,
                             audio: Bundle.main.url(forResource: "audio", withExtension: "m4a"),
                             onFinish: onFinish)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .statusBarHidden()
        .accessibilityHidden(true)
        .task {
            // Bez wideo – od razu dalej. Z wideo – zabezpieczenie, gdyby odtwarzanie utknęło.
            try? await Task.sleep(for: videoURL == nil ? .zero : .seconds(5))
            onFinish()
        }
    }
}

/// Odtwarzacz bez kontrolek (AVPlayerLayer wypełniający ekran). Jeden `AVPlayer` odtwarza
/// kompozycję obrazu i dźwięku, więc oba startują i kończą się razem.
private struct SplashPlayer: UIViewRepresentable {
    let video: URL
    let audio: URL?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIView(context: Context) -> PlayerView {
        let player = AVPlayer()
        player.preventsDisplaySleepDuringVideoPlayback = false

        let view = PlayerView()
        view.backgroundColor = UIColor(Theme.bg)
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        context.coordinator.load(into: player, video: video, audio: audio)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        // Znika po zakończeniu przejścia albo po pominięciu animacji – dźwięk milknie razem z nią.
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        private let onFinish: () -> Void
        private var tokens: [NSObjectProtocol] = []
        private var statusObservation: NSKeyValueObservation?

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        /// Równolegle: sesja audio (poza głównym wątkiem) i złożenie kompozycji; potem odtwarzanie.
        func load(into player: AVPlayer, video: URL, audio: URL?) {
            if audio == nil { SplashMedia.log("brak pliku audio.m4a w pakiecie aplikacji") }
            Task { [weak self, weak player] in
                async let session: Void = SplashAudioSession.activate()
                let asset: AVAsset
                do {
                    asset = try await SplashMedia.makeAsset(video: video, audio: audio)
                } catch {
                    SplashMedia.log("nie udało się złożyć obrazu z dźwiękiem: \(error) – samo wideo")
                    asset = AVURLAsset(url: video)
                }
                await session
                guard let self, let player else { return }
                let item = AVPlayerItem(asset: asset)
                self.observe(item, player: player)
                player.replaceCurrentItem(with: item)
            }
        }

        private func observe(_ item: AVPlayerItem, player: AVPlayer) {
            for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [onFinish] _ in
                    MainActor.assumeIsolated { onFinish() }
                })
            }
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak player] item, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.statusObservation != nil else { return }
                        switch item.status {
                        case .readyToPlay:
                            self.statusObservation = nil
                            player?.play()
                            SplashMedia.log("start odtwarzania (głośność multimediów: \(Int(AVAudioSession.sharedInstance().outputVolume * 100))%)")
                        case .failed:
                            self.statusObservation = nil
                            SplashMedia.log("błąd odtwarzania: \(String(describing: item.error))")
                            self.onFinish()
                        default:
                            break
                        }
                    }
                }
            }
        }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Sesja audio dla dźwięku startowego.
/// - `.playback` – dźwięk słychać także przy włączonym trybie cichym;
/// - `.mixWithOthers` – nie przerywa muzyki odtwarzanej w innych aplikacjach.
nonisolated private enum SplashAudioSession {
    /// `@concurrent` – wykonywane poza głównym wątkiem (`setActive` może blokować interfejs).
    @concurrent static func activate() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            SplashMedia.log("sesja audio: \(error)")
        }
    }
}
