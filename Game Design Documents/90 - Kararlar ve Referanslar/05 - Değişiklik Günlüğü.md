---
tür: değişiklik-günlüğü
durum: aktif
kapsam: GDD yönetim notlarının sürüm ve kapsam değişiklikleri
kaynaklar:
  - Kullanıcının ana tasarım özeti
  - PROJE.md
  - Taslak_fikir.md
  - docs/*.md
son_güncelleme: 2026-07-17
etiketler: [gdd, gdd/degisiklik]
---

# Değişiklik Günlüğü

## 2026-07-17 — GDD yönetim katmanı oluşturuldu

### Eklendi

- Modüler GDD yapısını, 01–08 klasörlerindeki mevcut 36 notu ve gerçek okuma sırasını tanımlayan [[00 - GDD Ana İndeks]].
- Kesinleşmiş kararları ayrı tutan [[01 - Karar Günlüğü]].
- Kaynak çelişkilerini otomatik karara bağlamadan izleyen [[02 - Çelişki ve Açık Karar Kaydı]].
- Kanonik alan dilini tanımlayan [[03 - Terimler Sözlüğü]].
- Ana tasarım özetinin 32 bölümünü kaynaklara ve hedef notlara eşleyen [[04 - Kaynak ve Kapsam Matrisi]].
- Statü, kaynak ve yazım kurallarını tanımlayan [[06 - Belge Yazım ve Statü Standardı]].

### Kabul edilen kararlar

- Modüler, eklentisiz Obsidian belge yapısı.
- Sözleşme → yük partisi → taşıma aşaması → servis hattı kanonik modeli.
- Fiziksel görünürlük ile büyük ölçekte güvenli toplulaştırmayı birleştiren hibrit simülasyon.
- Oyuncunun araç değil şirket yönettiği CEO ölçeği.
- Kullanıcının ana tasarım özetinin ürün önceliğinde ilk sırada olması.

### Açık bırakılanlar

- Kaynaklar arasında ürün veya teknik seçim gerektiren 12 konu [[02 - Çelişki ve Açık Karar Kaydı]] içine alındı.
- Açık konular için öneriler yazıldı; hiçbir öneri karar statüsüne yükseltilmedi.

### Korunanlar

- `PROJE.md`, `Taslak_fikir.md`, `docs/*.md` ve `Hoş geldiniz.md` kaynak olarak korundu; içerikleri değiştirilmedi.

## 2026-07-17 — Kasa bağlantıları doğrulandı

- Ana indeks, 01–08 klasörlerindeki gerçek 36 GDD notunu klasör sırasıyla bağlayacak biçimde güncellendi.
- Karar günlüğü ve kaynak-kapsam matrisi hayali hedeflerden gerçek kanonik notlara taşındı.
- Kasa dışındaki `PROJE.md`, `Taslak_fikir.md` ve `docs/*.md` kaynakları düz proje yolları olarak korundu.

## 2026-07-17 — İlk kritik karar paketi sonuçlandı

- Uzak şehirde şube veya depo kuruluşu için hedef şehirde şirket aracı bulunması şartı kaldırıldı.
- Standart sözleşmelerin araç sayısı yerine kapasite, sefer sıklığı ve SLA istemesi kabul edildi.
- Belirli araç sayısı veya ayrılmış filo şartı yalnız `dedicated fleet` sözleşmelerine ayrıldı.
- [[02 - Çelişki ve Açık Karar Kaydı]] içindeki iki çelişki kapatıldı; açık karar sayısı 10'a düştü.

#gdd #gdd/degisiklik
