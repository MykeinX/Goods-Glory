---
tür: belge-standardı
durum: kabul-edildi
kapsam: GDD notlarının yazım, kaynak, statü ve bağlantı kuralları
kaynaklar:
  - Kullanıcının ana tasarım özeti
  - PROJE.md
  - Taslak_fikir.md
  - docs/*.md
son_güncelleme: 2026-07-17
etiketler: [gdd, gdd/standart]
---

# Belge Yazım ve Statü Standardı

## 1. Temel ilke

Her not tek ana sorumluluk taşır ve bir konunun kanonik kaynağı olur. Başka bir not aynı bilgiyi yeniden yazmak yerine wikilink verir. Harici Obsidian eklentisi gerektiren sorgu, görünüm veya sözdizimi kullanılmaz.

## 2. Zorunlu frontmatter

Her GDD notu şu alanları içerir:

```yaml
---
tür: sistem-tasarımı
durum: öneri
kapsam: Notun sınırını açıklayan kısa ifade
kaynaklar:
  - Kaynak dosya veya karar
son_güncelleme: YYYY-AA-GG
etiketler: [gdd, gdd/sistem]
---
```

- `tür`: Notun bilgi işlevi; örneğin `ana-indeks`, `sistem-tasarımı`, `karar-günlüğü`.
- `durum`: Aşağıdaki statülerden biri.
- `kapsam`: Nota dahil olan konuyu ve sınırını tek cümlede açıklar.
- `kaynaklar`: Bilginin geldiği dosya, kullanıcı kararı veya prototip kanıtı.
- `son_güncelleme`: İçerik anlamının son değiştiği tarih.
- `etiketler`: En az `gdd`; gerektiğinde `gdd/karar`, `gdd/sistem` gibi alt etiket.

## 3. Belge statüleri

| Statü | Anlamı | Karar gücü |
|---|---|---|
| `ham-fikir` | İşlenmemiş kaynak düşünce | Yok |
| `öneri` | Tartışılabilir tasarım yaklaşımı | Yok |
| `test-edilecek` | Ölçütü tanımlanmış prototip varsayımı | Kanıt bekler |
| `kabul-edildi` | Ürün sahibi tarafından açıkça onaylanmış karar | Bağlayıcı |
| `uygulandı` | Çalışan prototipte gözlenebilen davranış | Yalnız tanımlı kapsamda kanıt |
| `ertelendi` | Aktif kapsam dışında, reddedilmemiş konu | Yok |
| `geçersiz` | Yeni karar tarafından yürürlükten kaldırılmış bilgi | Tarihçe için korunur |
| `aktif` | İndeks, günlük ve standart gibi yaşayan yönetim notu | İçeriğine göre |

`uygulandı`, otomatik olarak nihai ürün kararı değildir. Bir prototip davranışı tasarım açısından değiştirilebilir.

## 4. Kaynak önceliği

Çelişki durumunda:

1. Kullanıcının kapsamlı ana tasarım özeti
2. [[01 - Karar Günlüğü]] içindeki kabul edilmiş kararlar
3. Çalışan prototipin doğrulanmış davranışı
4. Ürün vizyonu
5. Sistem tasarım önerileri
6. Ham fikirler

Alt öncelikli metin sessizce silinmez veya yeniden yorumlanmaz. Çelişki [[02 - Çelişki ve Açık Karar Kaydı]] içine kaynak, etki, öneri ve durumuyla yazılır.

## 5. Karar kaydı biçimi

Her kabul edilmiş karar şunları içerir:

- benzersiz kimlik,
- kısa başlık,
- durum,
- karar cümlesi,
- gerekçe,
- etkilenen notlar,
- kaynak,
- tarih.

Karar yalnızca açık ürün sahibi onayı veya önceden tanımlanmış karar kapısının sonucu ile `Kabul edildi` olur. Belge yazarı öneriyi otomatik karara çeviremez.

## 6. Açık karar biçimi

Her açık konu şunları içerir:

- benzersiz kimlik,
- kaynak veya çelişen kaynaklar,
- ürün/teknik etki,
- bağlayıcı olmayan öneri ya da doğrulama yöntemi,
- durum.

Karar verildiğinde madde silinmez; karar kimliğine bağlantı verilerek `Karara bağlandı` yapılır.

## 7. Dil ve terimler

- GDD'nin ana dili Türkçedir.
- Teknik veri kimlikleri ve kod sembolleri gerektiğinde İngilizce kalır.
- Kanonik kavramlar [[03 - Terimler Sözlüğü]] ile uyumlu yazılır.
- Kısa, doğrudan ve test edilebilir cümleler kullanılır.
- “Olmalı” öneriyi, “kabul edildi” bağlayıcı kararı ifade eder; ikisi karıştırılmaz.

## 8. Bağlantı ve dosya adlandırma

- Notlar iki basamaklı sıra numarası ve açıklayıcı Türkçe ad kullanır.
- Kasa içi bağlantı sözdizimi inline kod içinde örneğin `[[Klasör/Not|Görünen Ad]]` biçiminde gösterilir; gerçek bağlantılarda var olan kasa yolu kullanılır.
- Aynı ada sahip not riski varsa klasör yolu bağlantıya eklenir.
- Kaynak kod veya eski çalışma belgelerine normal dosya yolu ile atıf yapılır.
- Bir not silinmek yerine gerekiyorsa `geçersiz` statüsüne alınır ve yerine geçen nota bağlanır.

## 9. Değişiklik disiplini

Anlamlı her güncellemede:

1. İlgili notun `son_güncelleme` alanı değiştirilir.
2. Karar etkisi varsa [[01 - Karar Günlüğü]] güncellenir.
3. Açık çelişki etkisi varsa [[02 - Çelişki ve Açık Karar Kaydı]] güncellenir.
4. Kapsam eşleşmesi değişirse [[04 - Kaynak ve Kapsam Matrisi]] güncellenir.
5. Önemli değişiklik [[05 - Değişiklik Günlüğü]] içine kısa biçimde eklenir.

## 10. Tamamlanma ölçütü

Bir sistem notu, şu koşullar sağlanmadan `kabul-edildi` sayılmaz:

- amacı ve kapsam dışı alanları açık,
- kanonik terimleri tutarlı,
- giriş, durum ve çıktı ilişkileri tanımlı,
- oyuncuya gösterilen sonuç açıklanabilir,
- ilgili açık kararlar bağlantılı,
- prototipte test edilecekse ölçütleri yazılı,
- kaynakları izlenebilir.

#gdd #gdd/standart
