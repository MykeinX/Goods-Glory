---
tür: GDD
durum: öneri
kapsam: Başarı, kriz, başarısızlık ve oyun sonu
kaynaklar:
  - "`docs/02_OYUN_TASARIMI.md`"
  - "`docs/04_KARARLAR_VE_ACIK_SORULAR.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - gdd/çekirdek-oynanış
  - gdd/kriz
  - gdd/açık-karar
---

# Başarı, Kriz ve Başarısızlık

#gdd #gdd/çekirdek-oynanış #gdd/açık-karar

## Karar Durumu

Nihai başarı koşulu, kampanya yapısı ve şirketin tamamen iflas edip edemeyeceği açık karardır. Bu not, kabul edilmiş tasarım hedeflerini önerilen kriz modeliyle ayırır.

## Kabul Edilmiş Başarı Yönü

Başarı yalnızca nakit sayısının büyümesi değildir. Oyuncu:

- kârlı ve dayanıklı ağ kurar,
- hizmet sözlerini güvenilir biçimde karşılar,
- yeni şehir, ülke ve taşıma türlerine açılır,
- güçlü müşteri portföyü geliştirir,
- operasyonları otomatikleştirir,
- küresel ve tanınan bir marka oluşturur.

Başarı, oyuncunun seçtiği stratejiye göre farklı biçimlerde görünür olabilir:

- en güvenilir marka,
- en geniş ağ,
- en yüksek şirket değeri,
- belirli yük veya taşıma modunda uzmanlık,
- sürdürülebilir lojistik liderliği.

## Kriz Tasarımı

Krizler oyuncunun kurduğu sistemi sınayan, önceden kısmen okunabilen ve birden fazla çözümü olan durumlardır.

### Kriz Kaynakları

- nakit ve borç baskısı,
- kapasite aşımı,
- bakım birikimi,
- sözleşme hizmet seviyesi düşüşü,
- yakıt/enerji fiyatı artışı,
- liman, sınır veya terminal yoğunluğu,
- grev ve personel sorunu,
- hava ve doğal afet,
- regülasyon değişimi,
- büyük müşteri kaybı,
- rakip fiyat baskısı.

### İyi Kriz Kriterleri

- Mümkün olduğunda ön sinyal verir.
- En az iki makul tepki sunar.
- Farklı şirket stratejilerini farklı etkiler.
- Sonucu sebep zinciriyle açıklar.
- Hazırlıklı oyuncuyu ödüllendirir.
- Tek bir rastgele olayla uzun emeği silmez.

## Toparlanabilir Kriz Modeli

**Öneri — kabul edilmiş nihai karar değildir:** Ana oyun, ani ve geri döndürülemez “game over” yerine toparlanabilir krizlere öncelik versin.

Toparlanma araçları:

- maliyet kesintisi ve operasyon küçültme,
- zarar eden hat veya sözleşmeden çıkış,
- varlık satışı,
- borç yeniden yapılandırma,
- geçici kredi veya yatırımcı,
- dış kapasite kullanımı,
- yönetim değişikliği,
- güvenilirliği yeniden kazanma programı.

Bu model başarısızlığı etkisizleştirmemelidir. Toparlanma; zaman, itibar, kontrol, gelecekteki gelir veya şirket payı gibi anlamlı bedeller taşımalıdır.

## Nihai İflas Açık Kararı

Aşağıdaki seçeneklerden biri ayrıca onaylanmalıdır:

1. **Tam iflas mümkündür:** Borç ve yükümlülükler sürdürülemezse kayıt sona erer.
2. **Her zaman toparlanma vardır:** Ağır bedelle de olsa şirket devam eder.
3. **Mod bazlı yaklaşım:** Öğretici/sandbox modunda toparlanma, zorlu senaryoda nihai iflas mümkündür.

**Öneri:** Mod bazlı yaklaşım, farklı oyuncu beklentilerini karşılayabilir; fakat kapsam ve iletişim maliyeti kullanıcı testinden sonra değerlendirilmelidir.

## Oyun Sonu Açık Kararı

Nihai ürün için seçenekler:

- açık uçlu şirket modu,
- hedef tabanlı senaryolar,
- kampanya,
- öğretici senaryolar + açık uçlu ana mod.

**Öneri:** Kısa hedef tabanlı senaryolar prototip ve öğretim için; açık uçlu şirket modu uzun vadeli fantezi için birlikte değerlendirilsin. Bu henüz kabul edilmiş ürün kararı değildir.

## Geri Bildirim

Her başarısız sonuç şunları açıklar:

- ne oldu,
- hangi karar veya koşullar etkiledi,
- erken sinyal var mıydı,
- finans ve itibar etkisi nedir,
- oyuncu şimdi hangi seçeneklere sahiptir.

Çevrimdışı süreçte büyük krizler oyuncu yokken geri döndürülemez sonuç üretmez; karar için bekler. Ayrıntılar [[03 - Zaman ve Çevrimdışı İlerleme]] notundadır.

## İlgili Notlar

- [[01 - Ana Oynanış Döngüsü]]
- [[03 - Zaman ve Çevrimdışı İlerleme]]
- [[01 - Ürün Vizyonu/02 - Tasarım Sütunları|Tasarım Sütunları]]
- [[05 - İlerleme ve İçerik/03 - Yük Türleri ve Özel Operasyonlar|Yük Türleri ve Özel Operasyonlar]]
