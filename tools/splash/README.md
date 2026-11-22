# Animacja startowa

`subbi/Splash/splash.mp4` (2,2 s, 1080×2340, 60 kl./s, H.264, bez dźwięku) jest generowany przez `make_splash.swift`:

```sh
swiftc -O -o /tmp/make_splash tools/splash/make_splash.swift
/tmp/make_splash subbi/Splash/splash.mp4
```

Ruch (tor lotu, sprężyste lądowanie, smuga, poświata) i czas trwania ustawia się w `make_splash.swift`.

**Kolory:** wideo jest oznaczone jako BT.709, a systemy Apple wyświetlają takie wideo z gammą 1,961. Dlatego klatki są rysowane w przestrzeni `videoSpace` (prymarne kolory sRGB, gamma 1,961). Bez tego tło po odtworzeniu jest jaśniejsze (36 45 80 zamiast 31 41 69) i widać przeskok koloru względem ekranu startowego. Po zmianie generatora sprawdź kolor pierwszej klatki, np. przez `AVAssetImageGenerator`.

**Dźwięk:** `subbi/Splash/audio.m4a` (2,2 s, AAC, stereo), generowany przez `make_audio.py`. Składa się ze świstu przelotu (prawo → środek), dwóch uderzeń basem strojonych do A (0,70 s i 1,00 s), dzwoneczków A-dur przy lądowaniu i pogłosu:

```sh
python3 tools/splash/make_audio.py /tmp/splash-audio.wav
afconvert -f m4af -d aac -b 192000 /tmp/splash-audio.wav subbi/Splash/audio.m4a
```

Czasy uderzeń ustawia się w `HITS`, głośność warstw w `WHOOSH_LEVEL`, `CHIME_LEVEL` i `REVERB_WET`, a ogólną głośność w `VOLUME_DB` (teraz −4 dB). Po zmianach sprawdź, czy plik po kodowaniu AAC nie przesterowuje (`PEAK_DBFS`). `SplashMedia` łączy dźwięk z wideo w jedną kompozycję odtwarzaną jednym `AVPlayer`. Jeśli dźwięk jest dłuższy od wideo, ostatnia klatka trwa do jego końca. Poprzedni, ręcznie dodany dźwięk leży w `original-audio.mov` (nie trafia do aplikacji). Żeby do niego wrócić, przekonwertuj go do `audio.m4a`.

Pierwsza klatka ma kolor `LaunchBackground` (ekran startowy iOS, `UILaunchScreen` w `subbi-Info.plist`), a ostatnia pokazuje logo na środku, z którego `SplashView` przechodzi w aplikację.
