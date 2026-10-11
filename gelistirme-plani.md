# Nöbet Listesi Uygulaması: Aşamalı Geliştirme Planı

Flutter (Android + iOS), tek kullanıcı, sunucu ve uzak veritabanı yok; tüm veriler telefonda saklanır.

Bu belge iki iş görür:
1. Her aşamada (Level) ne yapılacağını, hangi model, ekran ve fonksiyonların gerektiğini ve aşama bitince neyin çalışır olacağını anlatır.
2. Her aşamanın sonunda **Claude Code'a doğrudan yapıştırabileceğin bir komut** vardır. Aşamaları sırayla ver, her aşamayı test edip çalıştığını görmeden bir sonrakine geçme.

---

## 0. Önce netleştirilmesi gereken bir kural

> "Herkes en fazla 2 gün aşırı nöbet tutabilecek."

Bu cümle iki şekilde okunabiliyor ve algoritmayı doğrudan etkiliyor:

| Yorum | Anlamı | Örnek |
|---|---|---|
| **A) Gün aşırı zinciri** (seçilen) | Gün aşırı nöbet zinciri en fazla 2 nöbet uzunluğunda olabilir. Ay içinde kaç kez olduğu sınırsız. | 3-5, 12-14, 19-21 olur; 3-5-7 olmaz. |
| **B) Fazla nöbet** | Bir kişi, kendi grubunun ortalamasından en fazla 2 nöbet fazla tutabilir. | Ortalama 8 ise en fazla 10. |

**Karar: A geçerli kuraldır.** Kural: bir kişi d, d+2 ve d+4 günlerinin üçünde birden nöbet tutamaz. Ayrı ayrı gün aşırı çiftlerin sayısına sınır yoktur, ama **çift sayısı kişiler arasında olabildiğince eşit dağıtılır** (öncelik adalet). B ayarlarda isteğe bağlı ek kural olarak durur ve varsayılan olarak kapalıdır. Ayrıca her iki durumda da geçerli olan bir kural ekledim: **24 saatlik nöbetin ertesi günü aynı kişiye nöbet verilmez** (art arda iki gün yok). Bunu istemezsen ayardan kapatılabilir.

---

## 1. Teknik tercihler

| Konu | Öneri | Neden |
|---|---|---|
| Yerel saklama | **Hive CE** (`hive_ce`, `hive_ce_flutter`) | Sunucusuz, hızlı, kurulumu kolay; kişiler, aylar, tatiller gibi nesneleri doğrudan saklar. `shared_preferences` sadece ayarlar için uygun, aylık geçmiş için yetersiz. `sqflite` da olur ama bu veri yapısı için gereğinden ağır. |
| Durum yönetimi | **Riverpod** (`flutter_riverpod`) | Basit, test edilebilir, Claude Code'un iyi bildiği bir yapı. |
| Tarih / Türkçe | `intl` + `flutter_localizations` (tr_TR) | Ay ve gün adlarının Türkçe görünmesi için. |
| Takvim seçici | `table_calendar` | İstenmeyen günleri takvimden dokunarak seçmek için. |
| Dışa aktarma | `pdf` + `printing`, `share_plus` | Listeyi PDF yapıp WhatsApp vb. ile paylaşmak için. |
| Yedekleme | `file_picker` + `share_plus` | Veriler sadece telefonda olduğu için JSON yedeği kritik. |

**Önemli prensip:** Nöbet dağıtım algoritması ve mesai hesabı **saf Dart** (Flutter'a bağımlı olmayan) sınıflarda yazılacak ve birim testleriyle doğrulanacak. Ekranlar bu sınıfları sadece çağıracak.

### Klasör yapısı

```
lib/
  main.dart
  app.dart                     # tema, Türkçe locale, yönlendirme
  models/                      # Person, Role, Holiday, MonthPlan, Assignment, RosterSettings
  data/                        # Hive kutuları, repository sınıfları, Türkiye tatil verisi
  logic/                       # roster_generator.dart, work_hours_calculator.dart, validator.dart
  features/
    people/                    # kişi listesi + ekle/düzenle
    month/                     # ay seçimi, istenmeyen günler
    holidays/                  # resmi tatil yönetimi
    roster/                    # oluşturulan liste + özet tablo
    settings/                  # kurallar, yedekleme, tema
test/
  logic/                       # algoritma ve hesap testleri
```

---

## 2. Aşamalar

### Level 0: Proje iskeleti ve kurallar dosyası

**Yapılacaklar**
- `flutter create` ile proje, paketlerin eklenmesi, klasör yapısı.
- Türkçe locale, Material 3 tema, alt menü (Kişiler, Ay Planı, Tatiller, Ayarlar).
- Proje köküne **`CLAUDE.md`**: iş kurallarını yaz (aşağıdaki "İş kuralları özeti"). Claude Code her oturumda bu dosyayı okur, böylece kuralları her seferinde tekrar anlatmana gerek kalmaz.

**Bitince çalışan:** Boş sekmeli uygulama telefonda/emülatörde açılır, tarihler Türkçe görünür.

**Claude Code komutu**
```
Flutter ile Android ve iOS için "nobet_listesi" adında bir uygulama başlat.
Paketler: flutter_riverpod, hive_ce, hive_ce_flutter, intl, flutter_localizations, table_calendar, uuid.
Dev: hive_ce_generator, build_runner, flutter_lints.
Klasör yapısı: lib/models, lib/data, lib/logic, lib/features/{people,month,holidays,roster,settings}, test/logic.
Uygulama Türkçe (tr_TR) olsun, Material 3 kullan, alt navigasyonda 4 sekme olsun: Kişiler, Ay Planı, Tatiller, Ayarlar (şimdilik boş sayfalar).
Proje köküne CLAUDE.md oluştur ve içine şu iş kurallarını yaz: [aşağıdaki "İş kuralları özeti" bölümünü buraya yapıştır].
Algoritma ve hesap mantığı lib/logic altında Flutter'dan bağımsız saf Dart olmalı ve test edilmeli kuralını da CLAUDE.md'ye ekle.
```

---

### Level 1: Veri modelleri ve yerel saklama

**Modeller**
- `Role` (enum): `nurse` (Hemşire), `radiologyTech` (Radyoloji Teknikeri).
- `Person`: `id`, `name`, `role`, `isActive` (ayrılan kişiyi silmeden pasifleştirmek için), `colorValue` (listede ayırt etmek için, isteğe bağlı).
- `Holiday`: `date`, `name`, `isHalfDay` (arife günleri için), `isPredefined`.
- `MonthPlan`: `year`, `month`, `unavailableDays: Map<personId, List<int>>` (ayın günleri), `assignments: Map<int, DayAssignment>`, `generatedAt`, `isLocked`.
- `DayAssignment`: `day`, `nurseIds: List<String>` (2 kişi), `techId: String` (1 kişi).
- `RosterSettings`: `nursesPerDay = 2`, `techsPerDay = 1`, `shiftHours = 24`, `dailyRequiredHours = 7`, `maxEveryOtherDayChain = 2` (gün aşırı zincirindeki en fazla nöbet sayısı), `maxExtraOverAverage = null` (kapalı; açılırsa 2 önerilir), `forbidConsecutiveDays = true`, `holidayCountsAsWeekend = true`.

**Saklama**
- Her model için Hive adaptörü; `PeopleRepository`, `MonthPlanRepository`, `HolidayRepository`, `SettingsRepository`.
- Repository'ler Riverpod provider olarak sunulur.

**Bitince çalışan:** Veriler kaydedilip uygulama kapatılıp açıldığında geri gelir (henüz arayüz yok, testle doğrulanır).

**Claude Code komutu**
```
lib/models altında şu modelleri oluştur ve Hive CE adaptörlerini üret:
Role enum (nurse, radiologyTech; Türkçe görünen adları: Hemşire, Radyoloji Teknikeri),
Person (id, name, role, isActive, colorValue),
Holiday (date, name, isHalfDay, isPredefined),
DayAssignment (day, nurseIds, techId),
MonthPlan (year, month, unavailableDays Map<String, List<int>>, assignments Map<int, DayAssignment>, generatedAt, isLocked),
RosterSettings (nursesPerDay=2, techsPerDay=1, shiftHours=24, dailyRequiredHours=7, maxEveryOtherDayChain=2, maxExtraOverAverage=null (int?, null ise kural kapalı), forbidConsecutiveDays=true, holidayCountsAsWeekend=true).
lib/data altında her biri için repository sınıfı yaz, main.dart'ta Hive'ı başlat, repository'leri Riverpod provider olarak sun.
Modeller için toJson/fromJson da ekle (ileride yedekleme için gerekecek). Repository'ler için basit testler yaz.
```

---

### Level 2: Kişi yönetimi ekranı

**Ekranlar**
- **Kişiler listesi:** Rol başlığına göre gruplu (Hemşireler / Radyoloji Teknikerleri), her grupta kişi sayısı.
- **Ekle/Düzenle formu:** Ad, rol seçimi, aktif/pasif.
- Kaydırarak silme, silmeden önce onay; geçmiş listelerde adı geçen kişi silinmek yerine pasifleştirilir.

**Bitince çalışan:** Kişileri ekleyip düzenleyebilir, uygulamayı kapatıp açınca kalıcı olduklarını görürsün.

**Claude Code komutu**
```
Kişiler sekmesini yap: kişileri role göre gruplu listele (Hemşireler, Radyoloji Teknikerleri), her grup başlığında kişi sayısı olsun.
Sağ altta + butonu ile ad ve rol seçilen bir form aç; aynı form düzenleme için de kullanılsın.
Kaydırarak silme olsun, onay sorsun. Kişi herhangi bir MonthPlan içinde geçiyorsa silmek yerine pasif yap ve kullanıcıya bunu söyle.
Pasif kişiler listenin altında soluk görünsün.
```

---

### Level 3: Resmi tatiller ve mesai hesabı

**Tatil yaklaşımı (ikisi birlikte)**
1. **Önceden tanımlı Türkiye tatilleri:**
   - Sabit tarihliler her yıl otomatik: 1 Ocak, 23 Nisan, 1 Mayıs, 19 Mayıs, 15 Temmuz, 30 Ağustos, 29 Ekim.
   - Dini bayramlar her yıl kayar, bu yüzden yıl bazlı bir tabloda tutulur (Ramazan Bayramı 3 gün, Kurban Bayramı 4 gün, arifeler yarım gün). 2026 için: Ramazan Bayramı 20 to 22 Mart (arife 19 Mart), Kurban Bayramı 27 to 30 Mayıs (arife 26 Mayıs). Sonraki yıllar için tabloya Diyanet takvimine göre tarih eklenir; Claude Code'dan doldurmasını istedikten sonra tarihleri mutlaka kontrol et.
   - 28 Ekim (29 Ekim arifesi) de yarım gün.
2. **Elle düzenleme:** Tatiller ekranında ay ay liste; tatil ekleme, silme, yarım gün işaretleme. Örneğin hükümetin ilan ettiği köprü izinleri elle eklenir.

**Mesai hesabı (`WorkHoursCalculator`, saf Dart)**
- `requiredHours(year, month)` = (o aydaki Pazartesi to Cuma günlerinden resmi tatil olmayanların sayısı) × 7.
- Yarım gün tatil (arife) için varsayılan: o gün 3,5 saat sayılır. Bunu istemezsen ayardan "arifeyi tam iş günü say" seçilebilir.
- `workedHours(person)` = nöbet sayısı × 24.
- `overtimeHours` = max(0, çalışılan − gereken). Eksik çalışma varsa negatif değeri ayrıca "eksik saat" olarak gösterebiliriz.

**Örnek (Ekim 2026):** 22 hafta içi gün, 29 Ekim Perşembe tatil, 28 Ekim Çarşamba yarım gün. Gereken = 20 × 7 + 3,5 = 143,5 saat. 7 nöbet tutan kişi: 168 saat, fazla mesai 24,5 saat.

**Bitince çalışan:** Tatiller sekmesinde ayın tatilleri görünür ve düzenlenir; her ay için "Bu ay çalışılması gereken: X saat" bilgisi doğru hesaplanır.

**Claude Code komutu**
```
lib/data/turkish_holidays.dart dosyasında Türkiye resmi tatillerini tanımla:
sabit tarihliler (1 Ocak, 23 Nisan, 1 Mayıs, 19 Mayıs, 15 Temmuz, 30 Ağustos, 29 Ekim, 28 Ekim yarım gün) her yıl için üretilsin;
Ramazan ve Kurban Bayramı yıl bazlı tabloda olsun (arife yarım gün). 2026: Ramazan 20-22 Mart, arife 19 Mart; Kurban 27-30 Mayıs, arife 26 Mayıs.
2027 ve 2028 için Diyanet takvimine göre tarihleri ekle ve dosyada "doğrulanmalı" yorumu bırak.
İlk açılışta bu tatiller Hive'a isPredefined=true olarak yüklensin.
Tatiller sekmesi: ay seçici, o ayın tatil listesi, ekle/sil/yarım gün işaretle.
lib/logic/work_hours_calculator.dart: requiredHours(year, month, holidays, settings) = tatil olmayan hafta içi gün sayısı × dailyRequiredHours,
yarım gün tatil o gün için dailyRequiredHours/2 eklesin. workedHours = nöbet × shiftHours, overtime = max(0, worked - required).
Ekim 2026 için gereken saatin 143.5 çıktığını doğrulayan test dahil kapsamlı birim testleri yaz.
```

---

### Level 4: Ay seçimi ve istenmeyen günler

**Ekranlar**
- **Ay Planı ana ekranı:** Üstte ay seçici (◀ Ekim 2026 ▶). Altında aktif kişiler ve her birinin kaç istenmeyen günü olduğu.
- **Kişi istenmeyen gün seçimi:** O ayın takvimi; dokunulan günler kırmızı işaretlenir. Hafta sonları ve resmi tatiller takvimde farklı renkte gösterilir.
- **Uygunluk ön kontrolü (fizibilite):** Her gün için o gün nöbete uygun hemşire sayısı < 2 veya tekniker sayısı < 1 ise, liste oluşturmadan önce uyarı: "14 Ekim: uygun tekniker yok."
  - Toplam kapasite kontrolü: Örneğin 3 tekniker ve 31 gün varsa kişi başı ~10,3 nöbet düşer; art arda gün yasağı ve gün aşırı zincir yasağıyla bu mümkün olmayabilir. Bu durumda kullanıcıya hangi kuralın sorun çıkardığı söylenir.

**Bitince çalışan:** Bir ay seçip her kişinin istemediği günleri işaretleyebilir, imkânsız günler için önceden uyarı görürsün.

**Claude Code komutu**
```
Ay Planı sekmesi: üstte ay ileri/geri seçici, seçili ay için MonthPlan yoksa oluştur.
Aktif kişileri role göre gruplu listele, yanında istenmeyen gün sayısı yazsın.
Kişiye dokununca table_calendar ile o ayın takvimini aç; günlere dokunarak istenmeyen gün seç/kaldır, MonthPlan.unavailableDays içine kaydet.
Hafta sonları ve resmi tatiller takvimde farklı renkte olsun.
lib/logic/feasibility_checker.dart yaz: her gün için uygun hemşire < nursesPerDay veya uygun tekniker < techsPerDay olan günleri,
ve kişi sayısı/gün sayısı oranına göre forbidConsecutiveDays ile maxEveryOtherDayChain kurallarının karşılanamayacağı durumları raporlasın.
Ay Planı ekranının altında bu uyarıları göster. Testlerini yaz.
```

---

### Level 5: Nöbet dağıtım algoritması (uygulamanın kalbi)

Bu aşamada **sadece algoritma ve testleri** yazılır, arayüz bir sonraki aşamada.

#### Kısıtlar

**Sert kısıtlar (asla çiğnenmez)**
1. Her gün tam olarak 2 hemşire + 1 radyoloji teknikeri.
2. Kişi, istemediği günde nöbet tutmaz.
3. Aynı kişi art arda iki gün nöbet tutmaz (`forbidConsecutiveDays`).
4. Gün aşırı zinciri: Bir kişi gün aşırı en fazla `maxEveryOtherDayChain` (2) nöbet üst üste tutabilir. Yani d, d+2, d+4 üçlüsünün hepsinde nöbet yasak (3-5 olur, 3-5-7 olmaz); ayrı çiftlerin sayısı sınırsız.
5. (İsteğe bağlı, varsayılan kapalı) Kural B: Kişinin nöbet sayısı ≤ kendi grubunun ortalamasının üst değeri + `maxExtraOverAverage`.
6. (Önceki ay devri, Level 8'de) Önceki ayın son günü nöbet tutan kişi bu ayın 1'inde nöbet tutmaz.

**Yumuşak hedefler (puanla optimize edilir)**
- Toplam nöbet sayıları **aynı rol grubu içinde** eşit olsun. Hemşireler kendi aralarında, teknikerler kendi aralarında dengelenir (havuzlar farklı büyüklükte olduğu için ortalamaları da farklıdır).
- Hafta sonu nöbetleri (Cumartesi + Pazar; ayara göre resmi tatiller de) grup içinde eşit olsun.
- **Gün aşırı çift sayısı** grup içinde eşit olsun (kimse diğerlerinden daha çok gün aşırı yorulmasın).
- Nöbetler ay içinde mümkün olduğunca aralıklı dağılsın.

**Hedef sayılar:** Hemşire hedefi = (gün sayısı × 2) / hemşire sayısı. Örneğin 31 gün, 7 hemşire: 62 / 7 = 8,86, yani bazıları 9, bazıları 8 tutar. Bölüm tam çıkmıyorsa fark en fazla 1 olur; kimin fazla tutacağı önceki ayların toplamına göre seçilir (Level 8).

#### Yöntem: zor günden başlayan açgözlü atama + çoklu deneme + iyileştirme

1. **Günleri zorluğa göre sırala:** Uygun kişi sayısı en az olan gün önce doldurulur (hafta sonları ve çok kişinin istemediği günler öne çıkar). Böylece kolay günler zor günlerin adaylarını tüketmez.
2. **Her boş koltuk için aday puanı hesapla:** Sert kısıtları geçen her aday için ceza puanı:
   - `(mevcut nöbet sayısı − hedef)` × büyük ağırlık
   - gün hafta sonu ise `(mevcut hafta sonu sayısı − hafta sonu hedefi)` × büyük ağırlık
   - bu atama gün aşırı çift oluşturuyorsa `(mevcut gün aşırı sayısı − grup ortalaması)` × büyük ağırlık; çifti en az olan kişi tercih edilir
   - son nöbetine çok yakınsa küçük ceza
   En düşük puanlı aday seçilir; eşitlikte rastgele seçilir.
3. **Aday yoksa:** O deneme başarısız sayılır, neden kaydedilir (ör. "18 Ekim: tekniker kalmadı, Ali istemedi, Ayşe 17'de nöbetçi").
4. **Çoklu deneme:** Adımlar 1 to 3 farklı rastgele tohumla 300 to 500 kez çalıştırılır (telefonda 1 saniyenin altında sürer).
5. **Yerel iyileştirme:** En iyi sonuç üzerinde, aynı roldeki iki kişinin iki günlük nöbetini takas ederek toplam ceza puanını düşüren hamleler, iyileşme kalmayana kadar denenir.
6. **Sonuç:** Toplam puanı en düşük geçerli liste döner. Hiç geçerli liste bulunamazsa en sık takılınan günler ve sebepleri raporlanır.

**Puan fonksiyonu (liste geneli):** Grup içi toplam nöbet farklarının karesi + hafta sonu farklarının karesi + gün aşırı çift sayısı farklarının karesi. Üçü de aynı önemde tutulur, çünkü öncelik adalettir. Kare kullanmak, büyük dengesizlikleri küçüklerden çok daha fazla cezalandırır.

**Belirlenimci çıktı:** Tohum (seed) değeri `MonthPlan` içinde saklanır; "Yeniden oluştur" yeni tohum ile farklı ama yine dengeli bir liste üretir.

**Testler (algoritmanın doğru olduğunun kanıtı)**
- 31 günlük ay, 7 hemşire, 4 tekniker: her gün 2+1 dolu, kimse istemediği gün çalışmıyor, art arda gün yok.
- Grup içi en fazla ve en az nöbet farkı ≤ 1, hafta sonu farkı ≤ 1, gün aşırı çift sayısı farkı ≤ 1 (istenmeyen günler izin verdiği ölçüde).
- Hiçbir kişide 3'lü gün aşırı zincir yok (d, d+2, d+4); 2'li çiftler serbest.
- İmkânsız senaryo (bir günde kimse uygun değil) anlamlı hata mesajı döndürüyor.
- Aynı tohum aynı sonucu veriyor.

**Claude Code komutu**
```
lib/logic/roster_generator.dart içinde saf Dart bir RosterGenerator yaz. Girdi: yıl, ay, aktif kişiler, unavailableDays, tatiller, RosterSettings, seed, (opsiyonel) önceki ayın son günü nöbetçileri.
Çıktı: RosterResult { Map<int, DayAssignment> assignments, double score, List<RosterIssue> issues }.
Sert kısıtlar: her gün nursesPerDay hemşire + techsPerDay tekniker; istenmeyen günde atama yok; forbidConsecutiveDays ise art arda gün yok;
bir kişi gün aşırı en fazla maxEveryOtherDayChain nöbet üst üste tutabilir (varsayılan 2: d, d+2, d+4 üçünde birden nöbet yasak; 3-5 olur, 3-5-7 olmaz; ayrı çiftlerin sayısı sınırsız); maxExtraOverAverage null değilse kişi nöbeti ≤ ceil(grup ortalaması) + maxExtraOverAverage.
Yumuşak hedefler: rol grubu içinde toplam nöbet ve hafta sonu nöbeti (Cmt, Paz, holidayCountsAsWeekend ise resmi tatil) eşit; gün aşırı çift sayısı grup içinde eşit (adalet öncelikli, aynı ağırlıkta).
Yöntem: günleri uygun kişi sayısına göre zordan kolaya sırala, her koltuğa ceza puanı en düşük adayı ata (eşitlikte seed'li Random),
bunu 400 kez farklı seed türeviyle dene, en iyi sonucu aynı roldeki iki kişinin günlerini takas eden yerel iyileştirme ile geliştir.
Liste puanı: grup içi toplam nöbet sapmalarının karesi + hafta sonu sapmalarının karesi + grup içi gün aşırı çift sayısı sapmalarının karesi.
Geçerli liste bulunamazsa hangi günde hangi rolde neden tıkandığını RosterIssue olarak döndür.
test/logic/roster_generator_test.dart içine planımdaki testleri yaz: 2+1 doluluk, istenmeyen gün ihlali yok, art arda gün yok,
grup içi max-min nöbet farkı ≤ 1, hafta sonu farkı ≤ 1, gün aşırı çift sayısı farkı ≤ 1, 3'lü gün aşırı zincir yok, imkânsız senaryoda anlamlı hata, aynı seed aynı sonuç.
Tüm testler geçene kadar düzelt.
```

---

### Level 6: Liste ekranı ve özet tablo

**Ekran: Nöbet Listesi**
- Ay Planı ekranında **"Listeyi Oluştur"** butonu; ilerleme göstergesi, ardından liste.
- **Tablo:** Sütunlar günler (başlıkta gün numarası ve kısa gün adı: 1 Per, 2 Cum ...), satırlar: Hemşire 1, Hemşire 2, Radyoloji Teknikeri. Hafta sonu ve tatil sütunları renkli. Tablo yatay kaydırılır, satır başlıkları solda sabit kalır.
- **Tablonun sonunda özet tablo** (istenen şekilde), her kişi için:

| Ad | Görev | Toplam nöbet | Hafta sonu nöbet | Gün aşırı | Çalışılan saat | Çalışılması gereken saat | Fazla mesai |
|---|---|---|---|---|---|---|---|
| Ayşe | Hemşire | 9 | 3 | 2 | 216 | 143,5 | 72,5 |

- Grup ortalamaları özetin altında ayrı satır olarak.
- **"Yeniden oluştur"** (farklı tohum) ve **"Kaydet/Kilitle"** butonları. Kilitli ay yanlışlıkla yeniden oluşturulamaz.

**Bitince çalışan:** Uygulamanın ana amacı tamamlanır: kişileri girip istenmeyen günleri seçersin, tek dokunuşla dengeli liste ve sonunda nöbet sayısı, gereken saat ve fazla mesai özeti oluşur.

**Claude Code komutu**
```
Ay Planı ekranına "Listeyi Oluştur" butonu ekle: önce feasibility_checker çalışsın, sorun varsa göster ve yine de denemek isteyip istemediğini sor.
RosterGenerator'ı compute/Isolate ile çalıştır (arayüz donmasın), sonucu MonthPlan.assignments'a kaydet.
Yeni RosterScreen: sütunlar günler (başlıkta "1 Per", "2 Cum" gibi gün numarası ve kısa gün adı), satırlar Hemşire 1, Hemşire 2, Radyoloji Teknikeri; hafta sonu ve tatil sütunları farklı renk; tablo yatay kaydırılsın, soldaki satır başlıkları sabit kalsın.
Tablonun sonunda kişi başı özet tablo: Ad, Görev, Toplam nöbet, Hafta sonu nöbet, Gün aşırı çift sayısı, Çalışılan saat, Gereken saat, Fazla mesai (WorkHoursCalculator ile).
Altına rol grubu ortalamalarını yaz. "Yeniden oluştur" (yeni seed) ve "Kilitle" butonları olsun; kilitliyse yeniden oluşturma onay istesin.
```

---

### Level 7: Elle düzenleme ve kural uyarıları

Algoritma ne kadar iyi olsa da son sözü sen söylemek isteyeceksin (son dakika değişiklikleri, nöbet değişimleri).

**Özellikler**
- Tablodaki bir hücreye dokun, o gün için uygun kişileri listele; seçilen kişiyle değiştir.
- İki kişinin nöbetini takas et ("Ayşe 5 Ekim ↔ Fatma 12 Ekim").
- **Canlı doğrulama (`RosterValidator`):** Her değişiklikten sonra kurallar tekrar kontrol edilir; ihlal eden hücre turuncu/kırmızı işaretlenir, altta açıklama: "Mehmet 14 ve 15 Ekim art arda nöbette", "Zeynep istemediği güne (20 Ekim) atandı".
- İhlale izin verilir ama uyarı kalır (zorunlu durumlar için), özet tablo anında güncellenir.

**Bitince çalışan:** Oluşan listeyi elle düzeltebilir, hangi kuralı bozduğunu anında görürsün.

**Claude Code komutu**
```
lib/logic/roster_validator.dart: bir MonthPlan'ı RosterSettings'e göre doğrulayıp ihlal listesi döndürsün (gün, kişi, kural, Türkçe açıklama). Testlerini yaz.
RosterScreen'de hücreye dokununca bottom sheet aç: o gün o rol için kişiler, uygun olanlar üstte, kural bozacak olanlar uyarı ikonu ve sebebiyle altta.
Seçince ata. Uzun basınca "takas modu": ikinci bir hücre seçilince iki atamayı değiştir.
Her değişiklikte validator çalışsın, ihlalli hücreler renklensin, ekranın altında ihlal listesi görünsün, özet tablo anında güncellensin.
```

---

### Level 8: Geçmiş aylar ve aylar arası adalet

**Özellikler**
- **Geçmiş:** Ay Planı'nda önceki aylara geçince kayıtlı listeler görünür (salt okunur, kilidi açılabilir).
- **Önceki ay devri:** Yeni ay oluşturulurken önceki ayın son 4 gününün nöbetçileri (art arda gün ve gün aşırı zincir kuralı için) dikkate alınır.
- **Yıllık denge:** Bir ayda nöbet sayısı tam bölünmüyorsa (ör. 8,86) kimin 9 tutacağı, yıl içi toplamı en az olanlardan seçilir; aynısı hafta sonu ve gün aşırı sayıları için de geçerli. Böylece birkaç ay içinde herkes eşitlenir.
- **Yıllık özet ekranı:** Kişi başı yıl toplamı: nöbet, hafta sonu, fazla mesai saati.

**Bitince çalışan:** Aylar birbirine bağlanır, ay geçişlerinde kural ihlali olmaz ve yıl boyunca yük adil dağılır.

**Claude Code komutu**
```
RosterGenerator'a opsiyonel girdi ekle: previousMonthTail (önceki ayın son 4 gününün atamaları) ve yearToDateCounts (kişi başı yıl içi toplam, hafta sonu ve gün aşırı sayıları).
previousMonthTail ile art arda gün ve gün aşırı kurallarını ay sınırında da uygula.
Ortalama tam bölünmediğinde fazla nöbeti yearToDateCounts'u en düşük olanlara ver; hafta sonu ve gün aşırı için de aynısı.
Ay Planı oluşturulurken bu verileri MonthPlanRepository'den otomatik topla.
Yeni "Yıllık Özet" ekranı: yıl seçici, kişi başı toplam nöbet, hafta sonu nöbet, gün aşırı sayısı, toplam fazla mesai saati.
Ay sınırı kuralları için testler ekle.
```

---

### Level 9: Paylaşma, yedekleme, cilalama

**Özellikler**
- **PDF dışa aktarma:** Nöbet tablosu + özet tablo, A4 yatay, başlıkta ay/yıl. Paylaş menüsü (WhatsApp, e-posta, yazdır).
- **Görsel olarak paylaş:** Tabloyu PNG yapıp gruplara atmak için.
- **JSON yedekleme ve geri yükleme:** Veriler sadece telefonda olduğu için telefon değişince ya da uygulama silinince her şey kaybolur. Ayarlar'da "Yedeği dışa aktar" (tek JSON dosyası, Drive/WhatsApp'a kaydedilebilir) ve "Yedekten geri yükle".
- **Karanlık mod:** Sistem / açık / koyu.
- Uygulama ikonu ve adı (`flutter_launcher_icons`).

**Bitince çalışan:** Listeyi PDF veya görsel olarak paylaşabilir, verilerini güvenle yedekleyebilirsin.

**Claude Code komutu**
```
pdf, printing, share_plus, file_picker, flutter_launcher_icons paketlerini ekle.
RosterScreen'e "Paylaş" menüsü: PDF (A4 yatay, başlıkta "Ekim 2026 Nöbet Listesi", nöbet tablosu + özet tablo, Türkçe karakterler için uygun font gömülü)
ve PNG görsel (RepaintBoundary ile) seçenekleri.
Ayarlar sekmesi: RosterSettings değerlerini düzenleme (gün aşırı zincir uzunluğu, fazla nöbet limiti, art arda gün yasağı, tatili hafta sonu say, arifeyi yarım gün say),
tema seçimi (sistem/açık/koyu), "Yedeği dışa aktar" (tüm Hive verisi tek JSON, share_plus ile) ve "Yedekten geri yükle" (file_picker, onaylı, üzerine yazar).
Yedek/geri yükleme için gidiş-dönüş testi yaz.
```

---

## 3. Önerdiğim ek özellikler

Değer katanlar, önem sırasıyla. İlk dördü yukarıdaki aşamalara zaten dahil edildi.

1. **JSON yedekleme** (Level 9): Sunucu olmadığı için tek güvencen bu. Ayda bir yedek almanı hatırlatan küçük bir bildirim de eklenebilir.
2. **Elle düzenleme ve canlı kural uyarısı** (Level 7): Gerçek hayatta liste her zaman değişir; kuralları bozduğunda anında görmek en çok işine yarayacak özellik.
3. **PDF/görsel paylaşım** (Level 9): Listeyi ekibe ulaştırmanın en hızlı yolu.
4. **Aylar arası devir ve yıllık adalet** (Level 8): Ay sonu/başı ihlallerini ve "hep aynı kişi fazla tutuyor" şikâyetini önler.
5. **İzin/rapor günleri:** İstenmeyen günden farklı olarak, izinli/raporlu günler o kişinin **çalışması gereken saatinden düşülür** (kamu hastanelerinde genelde böyle hesaplanır). Bu, fazla mesai hesabını doğru yapar. Level 6'dan sonra eklemek kolay: istenmeyen gün seçerken "izin" türü işaretlenir.
6. **Tercih edilen günler (yumuşak istek):** "Mümkünse cuma ver" gibi; algoritmada sadece puanı düşürür, zorunlu değildir.
7. **Kişi bazlı nöbet limiti:** Örneğin yarı zamanlı ya da yeni başlayan biri için "bu ay en fazla 5 nöbet".

Bilerek önermediklerim: sürükle-bırak (telefonda dar tabloda zahmetli; dokun-seç ve takas daha pratik), bulut senkronizasyonu ve bildirim zamanlayıcıları (sunucusuz tek kullanıcı hedefine ters).

---

## 4. İş kuralları özeti (CLAUDE.md'ye yapıştır)

```
# Nöbet Listesi: İş Kuralları
- Tek kullanıcı, çevrimdışı; tüm veri Hive ile cihazda.
- Roller: Hemşire, Radyoloji Teknikeri.
- Her gün: 2 hemşire + 1 radyoloji teknikeri, nöbet 24 saat.
- Kişi istemediği günde asla nöbet tutmaz.
- Aynı kişi art arda iki gün nöbet tutmaz (ayarla kapatılabilir).
- Gün aşırı zincir en fazla 2 nöbet: 3-5 olur, 3-5-7 olmaz (d, d+2, d+4 üçünde birden nöbet yasak). Ayrı gün aşırı çiftlerin sayısı sınırsız (ayarlanabilir).
- (İsteğe bağlı, varsayılan kapalı) Kişi, rol grubunun ortalamasından en fazla N fazla nöbet tutabilir.
- Toplam nöbet, hafta sonu nöbeti ve gün aşırı çift sayısı rol grubu içinde eşit dağıtılır (fark ≤ 1 hedef). Öncelik adalet.
- Hafta sonu = Cumartesi + Pazar (+ resmi tatiller, ayarla).
- Gereken saat = ayın resmi tatil olmayan hafta içi günleri × 7; arife yarım gün = 3,5 saat.
- Çalışılan saat = nöbet × 24; fazla mesai = max(0, çalışılan − gereken).
- Liste sonunda kişi başı: toplam nöbet, hafta sonu nöbet, çalışılan saat, gereken saat, fazla mesai.
- Algoritma ve hesaplar lib/logic altında saf Dart, birim testli; arayüz metinleri Türkçe.
```

---

## 5. Claude Code ile çalışırken ipuçları

- Her aşamadan önce "Önce plan çıkar, onaylayınca kodla" diye başlarsan beklenmedik büyük değişikliklerin önüne geçersin.
- Her aşama sonunda `flutter test` ve `flutter analyze` çalıştırmasını iste; Level 5'te testler geçmeden ilerleme.
- Aşama bitince git ile commit at ("Level 3 tamam"); bir şey bozulursa geri dönmek kolay olur.
- iOS'a yüklemek için Mac + Xcode gerekir; Android için USB ile telefonu bağlayıp `flutter run` yeterli. Önce Android'de geliştirip sonra iOS'ta denemek pratik.
- Gerçek verinle (kendi ekibinin isimleri ve geçen ayın listesi) Level 6 sonunda deneme yap; algoritma ağırlıklarını ona göre ayarlatırsın.
