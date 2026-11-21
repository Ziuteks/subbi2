# Ikony serwisów (logo marek)

Kafelki w `subbi/Assets.xcassets/Brands/brand-*.imageset` (PNG @1x/@2x/@3x, 64 pt) są generowane z plików SVG w `svg/`:

```sh
swiftc -o /tmp/make_tiles tools/brand-icons/make_tiles.swift
/tmp/make_tiles tools/brand-icons/svg subbi/Assets.xcassets/Brands /tmp/brand-tiles-preview.png
```

Tło, kolor logo i wielkość logo na kafelku ustawia się w tablicy `tiles` w `make_tiles.swift`. W aplikacji serwis wskazuje kafelek przez `symbol: "brand:<nazwa>"` (`Service.catalog`).

## Źródła

| Plik | Źródło | Licencja (prawo autorskie) |
|---|---|---|
| `si-*.svg` (Netflix, Spotify, YouTube, iCloud, Apple TV, HBO Max, Dropbox, Notion, Claude) | [Simple Icons](https://simpleicons.org) 16.36.0 | CC0 1.0 |
| `adobe-mark.svg` | Wikimedia Commons, [Adobe Corporate logo.svg](https://commons.wikimedia.org/wiki/File:Adobe_Corporate_logo.svg), wycięty sam znak „A” | domena publiczna |
| `wm-primevideo-square.svg` | Wikimedia Commons, [Amazon Prime Video logo (2024).svg](https://commons.wikimedia.org/wiki/File:Amazon_Prime_Video_logo_(2024).svg) | domena publiczna |
| `wm-disneyplus.svg` | Wikimedia Commons, [Disney+ logo.svg](https://commons.wikimedia.org/wiki/File:Disney%2B_logo.svg) | domena publiczna |
| `wm-openai.svg` (ChatGPT) | Wikimedia Commons, [OpenAI logo 2025 (symbol).svg](https://commons.wikimedia.org/wiki/File:OpenAI_logo_2025_(symbol).svg) | domena publiczna |
| `wm-gemini.svg` + `wm-gemini.png` | Wikimedia Commons, [Google Gemini icon 2025.svg](https://commons.wikimedia.org/wiki/File:Google_Gemini_icon_2025.svg) | domena publiczna |
| `wm-microsoft365.svg` | Wikimedia Commons, [Microsoft 365 (2022).svg](https://commons.wikimedia.org/wiki/File:Microsoft_365_(2022).svg) | domena publiczna |

**Gemini** to wyjątek: SVG używa filtrów rozmycia, których renderer macOS (CoreSVG) nie obsługuje, więc generator korzysta z `wm-gemini.png`, wyrenderowanego przez Quick Look (WebKit):
`qlmanage -t -s 512 -o /tmp tools/brand-icons/svg/wm-gemini.svg` (wynik: `/tmp/wm-gemini.svg.png`).

Wszystkie logo są **znakami towarowymi** swoich właścicieli. Licencje powyżej dotyczą tylko prawa autorskiego do plików. Aplikacja używa logo wyłącznie do oznaczenia, którego serwisu dotyczy subskrypcja. Przed publikacją w App Store warto sprawdzić wytyczne marek (Apple, Amazon, Disney i Microsoft mają własne zasady używania logo).
