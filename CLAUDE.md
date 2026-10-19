# Nöbet Listesi: İş Kuralları
- Tek kullanıcı, çevrimdışı; tüm veri Hive ile cihazda.
- Roller: Hemşire, Radyoloji Teknikeri.
- Her gün: 2 hemşire + 1 radyoloji teknikeri, nöbet 24 saat.
- Kişi istemediği günde asla nöbet tutmaz.
- Aynı kişi art arda iki gün nöbet tutmaz (ayarla kapatılabilir).
- Gün aşırı zincir en fazla 2 nöbet: 3-5 olur, 3-5-7 olmaz (d, d+2, d+4 üçünde birden nöbet yasak). Ayrı gün aşırı çiftlerin sayısı sınırsız (ayarlanabilir).
- Nöbetler arası boşluk (aradaki boş gün) mümkünse en fazla 5; aşılırsa uyarı. Araya izin/pasif gün girerse sayılmaz. 4–5 günlük boşluk sayısı rol grubu içinde dengelenir.
- (İsteğe bağlı, varsayılan kapalı) Kişi, rol grubunun ortalamasından en fazla N fazla nöbet tutabilir.
- Toplam nöbet, hafta sonu nöbeti ve gün aşırı çift sayısı rol grubu içinde eşit dağıtılır (fark ≤ 1 hedef). Öncelik adalet: önce o ayın içindeki denge, ay içi denge sağlandıktan sonra yıl içi toplam (ay içi eşitken fazla nöbet yıl içinde az tutana).
- Hafta sonu = Cumartesi + Pazar (+ resmi tatiller, ayarla).
- Tam gün resmi (ulusal) tatil ve dini bayram (Ramazan/Kurban) nöbetleri ayrı ayrı sayılır ve dengelenir (ay içinde fark ≤ 1 hedef, yıl içinde az tutana öncelik).
- Şua izninden önceki 2 takvim gününde nöbet tutulmaz; şua dönüşü yıllık izin gibi ilk iş gününde nöbete başlanır (ay sınırını aşar).
- Gereken saat = ayın resmi tatil olmayan hafta içi günleri × 7; arife (yarım gün tatil) = 5 saat (ayarlanabilir).
- Çalışılan saat = nöbet × 24; fazla mesai = max(0, çalışılan − gereken).
- Liste sonunda kişi başı: toplam nöbet, hafta sonu nöbet, çalışılan saat, gereken saat, fazla mesai.
- Sorumlu hemşire (tek kişi): nöbet ortalamasına eşitlenmez; yalnızca seçtiği nöbet günlerine 24 yazılır (başka kimse olmasa da otomatik yazılmaz; seçmediği güne elle yazılırsa uyarı çıkar). Nöbet tutmadığı her mesai gününde 7A (gündüz, günün mesai saati kadar) çalışır; nöbet günü, nöbet ertesi ve izin günlerinde 7A'ya başka bir hemşire (adil sırayla) yazılır.
- Algoritma ve hesaplar lib/logic altında saf Dart, birim testli; arayüz metinleri Türkçe.

# Mimari ve kod kuralları
- `lib/logic` altındaki kod **saf Dart** olmalı: `package:flutter` import edilmez. Her sınıfın `test/logic` altında birim testi olur. Ekranlar bu sınıfları yalnızca çağırır.
- Durum yönetimi Riverpod (`flutter_riverpod`); repository'ler provider olarak sunulur.
- Yerel saklama Hive CE (`hive_ce`, `hive_ce_flutter`); adaptörler `hive_ce_generator` + `build_runner` ile üretilir:
  `dart run build_runner build` (üretilen `*.g.dart` ve `hive_adapters.g.yaml` commit edilir)
- Klasörler:
  - `lib/models`: Person, Role, Holiday, MonthPlan, DayAssignment, RosterSettings
  - `lib/data`: Hive kutuları, repository'ler, Türkiye tatil verisi
  - `lib/logic`: roster_generator, work_hours_calculator, feasibility_checker, roster_validator
  - `lib/features/{people,month,holidays,roster,statistics,settings}`: ekranlar
  - `lib/features/shell`: alt navigasyonlu ana iskelet
  - `lib/shared/widgets`: ortak widget'lar
- Locale `tr_TR`; tarihler `intl` ile Türkçe biçimlenir.
- Paylaş / yazdır / PNG'ye çevir / dosya seç işlemleri yalnızca `lib/shared/platform_services.dart` (`platformServicesProvider`) üzerinden çağrılır; testlerde `test/helpers.dart` içindeki `FakePlatformServices` ile override edilir.
- PDF'te Türkçe karakterler için `assets/fonts` altındaki Roboto gömülür (Apache 2.0).
- Uygulama adı "Nöbetçi". Uygulama ikonu `assets/icon/make_icon.py` ile çizilir (`python3 assets/icon/make_icon.py assets/icon`) → `dart run flutter_launcher_icons`. Araç `ios/Runner.xcodeproj/project.pbxproj` içinde `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` değerini bozar; o değişikliği geri al.
- Her değişiklikten sonra `flutter analyze` ve `flutter test` temiz geçmeli.
- Aşamalı plan: `gelistirme-plani.md`.
