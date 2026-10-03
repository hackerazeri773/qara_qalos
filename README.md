# ElnurTTS: iPhone için VoiceOver sesleri

ElnurTTS (RHVoice tabanlı) motorunu iOS'ta **sistem sesi** olarak çalıştırır.
VoiceOver ve Konuşan İçerik 12 sesi kullanabilir:

| Dil | Sesler |
|---|---|
| Azerbaycan dili | Elnur, Gulnar, Banu, Babek |
| Türkçe | Ahmet, Fahrettin, Emel, Faruk, Filiz Kompakt |
| Rusça | Svetlana, Dimitry |
| İngilizce | Jenny |

## Yapı

| Parça | Görevi |
|---|---|
| `Packages/ElnurTTSEngine` | ElnurTTS C/C++ motoru (v6.15.5 kaynakları), Android.mk ile aynı derleme ayarları |
| `ElnurKit` | Swift sarmalayıcı, ses/dil verileri (`Resources/ElnurData`) |
| `ElnurExtension` | VoiceOver için Speech Synthesis Provider Audio Unit eklentisi |
| `ElnurApp` | Sesleri sisteme tanıtan deneme uygulaması |
| `ElnurTests` | Simülatör testleri (Linux referans motoruyla karşılaştırma) |

## Android'den farklar

- **Sonic açık, en yüksek hız 5 kat** (Android: Sonic kapalı, 3 kat). VoiceOver kullanıcıları hızlı okuma tercih eder.
- **Elnur ve Faruk 16 kHz modeliyle** çalışır: bu iki sesin 24 kHz modelleri kırpılmış, bozuk ses üretiyor.
  `ElnurKit/Resources/ElnurVoices.json` içinde `"quality": "std"` yapılırsa 24 kHz kullanılır.
- Kalite ayarı ses başına seçilir (motor iki örnek tutar: `std` ve `min`).

## Önemli derleme notu

MAGE sentezleyicisi `ELNURTTS` tanımıyla derlenmelidir (Android.mk'deki gibi).
Bu tanım olmadan perde (lf0) verisi yanlış yorumlanır ve sesler bozulur.

## Derleme

GitHub Actions her `main` gönderiminde derler, simülatörde test eder ve
sonuçları (WAV dosyaları dahil) `ci-sonuc` dalına yazar.

## Lisans

Motor GPL (`Packages/ElnurTTSEngine/licenses`). HTS Engine, MAGE ve Sonic kendi lisanslarıyla.
