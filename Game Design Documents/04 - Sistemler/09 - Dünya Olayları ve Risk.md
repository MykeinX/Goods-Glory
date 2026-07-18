---
tür: GDD - sistem tasarımı
durum: Tasarım ilkesi kabul edilmiş; olay kataloğu test edilecek
kapsam: Dünya olayları, risk, sinyal, etki ve toparlanma
kaynaklar:
  - docs/02_OYUN_TASARIMI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - "[[03 - Kapasite ve Hibrit Simülasyon]]"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - olaylar
  - risk
---

# Dünya Olayları ve Risk

#gdd #olaylar #risk

## Amaç

Olaylar rastgele ceza kartı değil, oyuncunun ağ stratejisini sınayan görünür durumlardır. İyi olay:

- önceden sinyal verir;
- birden fazla çözüm sunar;
- farklı stratejileri farklı etkiler;
- fiziksel akışa bağlanır;
- sonucunu açıklar.

## Olay sınıfları

- hava ve doğal afet;
- yol, liman, demiryolu veya hava terminali kesintisi;
- yakıt/enerji ve kur şoku;
- grev, personel veya bakım problemi;
- ani talep artışı/düşüşü;
- müşteri veya tedarikçi krizi;
- regülasyon ve sınır değişikliği;
- siber/operasyon sistemi kesintisi;
- jeopolitik risk.

## Olay yaşam döngüsü

1. **Sinyal:** Tahmin, haber, müşteri uyarısı veya kapasite trendi.
2. **Hazırlık:** Yedek araç, slot, stok, rota ya da nakit kararı.
3. **Etki:** Belirli bölge, hat, tesis, mod veya yük türü etkilenir.
4. **Müdahale:** Yeniden yönlendirme, dış kaynak, öncelik veya hizmet kararı.
5. **Toparlanma:** Gecikme ve backlog temizlenir.
6. **Rapor:** Maliyet, teslimat ve itibar nedenleri açıklanır.

## Fiziksel etki

Olay soyut yüzdeden mümkün olduğunca gerçek kapasite sonuçlarına çevrilir:

- yol kapanışı seyahat süresini veya bağlantıyı değiştirir;
- depo olayı kapı/işleme kapasitesini düşürür;
- araç arızası belirli fiziksel görevi etkiler;
- talep artışı yeni yük partileri üretir;
- terminal kesintisi slotu kaçırır ve yükü kuyrukta bırakır.

Toplulaştırılmış mod aynı kapasite, maliyet ve teslimat sonucunu korur.

## Risk görünürlüğü

Oyuncuya:

- olasılık veya güven aralığı;
- beklenen başlangıç ve süre;
- etkilenen düğüm/hatlar;
- muhtemel kapasite kaybı;
- sözleşme ve yük partisi riski;
- hazırlık seçenekleri;
- en kötü makul sonuç

gösterilir. Uzun vadeli tahmin kesin değildir; belirsizlik yönetilebilir olmalıdır.

## Oyuncu seçenekleri

- yedek kapasite ayırma;
- erken sevk veya yük bekletme;
- alternatif rota/terminal;
- dış taşıyıcı slotu;
- düşük öncelikli yükü erteleme;
- yeni sözleşme kabulünü durdurma;
- riski kabul etme;
- müşteriden hizmet değişikliği isteme.

Her seçeneğin maliyet, hizmet ve itibar karşılığı görünürdür.

## Otomatik duraklatma

Küçük olaylar Logbook'a yazılır. Büyük kriz:

- stratejik sözleşme;
- kritik nakit;
- bölgesel kapasite çöküşü;
- kalıcı varlık kaybı riski

yaratıyorsa oyuncunun politikasına göre zamanı durdurabilir. Alarm yorgunluğu önlenir.

## Risk politikaları

Şirket:

- minimum kapasite rezervi;
- kabul edilen bağlantı tamponu;
- dış kaynak bütçesi;
- bakım eşiği;
- müşteri önceliği;
- bölgesel çeşitlendirme

tanımlayabilir. Risk sıfırlanmaz; maliyet ve dayanıklılık arasında seçim yapılır.

## Adalet

- Olay seed'li ve kayıtla kararlıdır.
- Kaydet/yükle sonucu yeniden çekmez.
- Oyuncunun göremeyeceği bilgiyle geriye dönük ceza verilmez.
- Kriz ciddi olabilir; fakat sebebi, etkisi ve toparlanma yolu anlaşılır olmalıdır.
- Gerçekçilik adına kontrol edilemeyen sürekli felaket üretilmez.

## İlgili belgeler

- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[05 - Multimodal Taşımacılık]]
- [[06 - Ekonomi ve Finans]]
- [[08 - Rakip Şirketler]]
- [[10 - Şirket Politikaları ve İtibar]]
