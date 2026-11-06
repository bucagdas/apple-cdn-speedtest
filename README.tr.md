# macOS için Apple CDN Speedtest

[English](README.md)

Mac'inizden Apple güncelleme sunucularını karşılaştırır. Go, Python, yapay zeka aracı veya hesap gerekmez. IPv4/IPv6 adreslerini bulur, sınırlı HTTPS indirmeleriyle hızlarını ölçer ve isteğe bağlı hosts satırlarını gösterir. Sistem ayarlarını değiştirmez ve güncelleme kurmaz.

## Başlangıç

1. **Code > Download ZIP** ile indirin ve klasörün tamamını çıkartın.
2. `start.command` dosyasına çift tıklayın, `tr` veya `en` seçin.
3. Veri bütçesini okuyup onaylayın, sonuçları bekleyin.

Finder dosyayı başlatamıyorsa çıkarttığınız klasörde Terminal açın:

```bash
bash macos/speedtest.sh --lang tr
```

macOS, Bash 3.2+, `dig` ve curl 8.4+ gerekir. `curl --version` ile sürümü kontrol edin; eski macOS sürümlerinde curl güncellemesi gerekebilir. Testi `sudo` ile çalıştırmayın. `macos` ve `config` klasörleri `start.command` yanında kalmalı.

## Kendi güncellemenizin URL adresini bulma

İndirdiğiniz gerçek dosyayı test etmek, genel bir örnek dosyaya göre daha anlamlıdır.

1. Sistem Ayarları > Genel > Yazılım Güncelleme bölümünden indirmeyi başlatın.
2. İndirme devam ederken çalıştırın:

```bash
bash macos/speedtest.sh --lang tr --find-url --yes
```

3. Araç, son bir saatin yerel `softwareupdated` kayıtlarını okuyup aday Apple ZIP/PKG adreslerini listeler. Dokümantasyon ve update-brain adreslerini eler. Öncelikle mevcut indirmenize ait `com_apple_MobileAsset_MacSoftwareUpdate` dosyasını seçin; SFR dosyaları ek güncelleme bileşenleridir. Birden fazla veya eski adres çıkabilir. Bu işlem güncel sürümünüzü otomatik belirlemez.
4. İlgili adresin tamamını kopyalayıp şu şekilde kullanın:

```bash
bash macos/speedtest.sh --lang tr --url 'TAM_HTTPS_ADRESINI_BURAYA_YAPISTIRIN'
```

Bazı kayıtlarda URL bulunmayabilir veya gizlenmiş olabilir. İndirme biraz ilerledikten sonra tekrar deneyin ya da `--url` vermeden hazır örnekleri kullanın. URL arama işlemi veri indirmez ve ayar değiştirmez. Tam kayıtlar dışarı gönderilmez; geçici kopyaları işlem bitince silinir.

Yalnızca `updates.cdn-apple.com` ve `swcdn.apple.com` üzerindeki doğrudan HTTPS dosya adresleri kabul edilir. DNS keşfi ve hosts önerisi URL'deki alan adı için yapılır. Bir çalıştırma boyunca tüm adaylar aynı dosya ve aralıklarla test edilir.

## Test URL'si çalışmazsa

`config/test-urls.txt` sıralı bir Apple örnek dosya listesi içerir. Bu dosyalar test verisidir, kurulacak sürüm önerisi değildir.

Hız testinden önce adreslerden bir bayt istenir. TLS, HTTP 206, Content-Range ve dosyanın yeterli büyüklükte olması kontrol edilir. Her URL kontrolü en fazla beş saniye sürer. İlk adres kaldırılmışsa sıradaki çalışan adres otomatik seçilir. Bu kontroller normal DNS çözümlemesini ve varsa mevcut hosts kayıtlarını kullanır.

Hiçbiri çalışmazsa:

- Etkileşimli kullanımda başka bir Apple HTTPS dosya adresi yapıştırmanız istenir.
- `--find-url` ile kendi güncellemenizin adresini arayıp `--url` ile verebilirsiniz.
- Ya da projenin güncel ZIP dosyasını indirebilirsiniz. Bakım yapan kişi yalnızca `config/test-urls.txt` listesini yenileyebilir; kod değişikliği gerekmez.

Başarısız kontrol, dosyanın silinmesi dışında ağ sorunu veya eski hosts kaydı nedeniyle de olabilir. `--url` verdiğinizde yalnızca o adres denenir; başka dosyaya sessizce geçilmez. Uzak kod veya otomatik proje güncellemesi indirilmez.

## DNS keşfi

Sistem DNS'ine ek olarak **10 sağlayıcıya ait 13 halka açık resolver adresi** sorgulanır. Tekrarlanan CDN IP'leri elenir. Sonuçtaki sağlayıcı adı, IP'yi ilk döndüren servistir; IP'nin sahibi veya sunucu konumu değildir.

Sağlayıcılar: Cloudflare, Google, Quad9, OpenDNS, AdGuard, Control D, CleanBrowsing, DNS.SB, DNS.WATCH ve DNSForge. `config/resolvers.txt` dosyasına her satırda `Ad IP` olacak şekilde adres ekleyip çıkartabilirsiniz. IPv4 resolver üzerinden hem IPv4 hem IPv6 kaydı sorgulanabilir.

Eklenen adreslerin kaynakları: [DNS.SB](https://dns.sb/guide/), [DNS.WATCH](https://dns.watch/) ve [DNSForge](https://dnsforge.de/). Daha fazla resolver aynı IP'leri döndürebilir ve keşif süresini uzatabilir. Yanıt vermeyen servisler atlanır.

Bu, tüm CDN sunucularının listesi değildir. `dig`, macOS'un varsayılan DNS yapılandırmasını kullanır; VPN veya alan adına özel çözümlemeden farklı olabilir. Ağınız halka açık DNS'i engelleyebilir veya sorguları başka yere yönlendirebilir. Resolver servislerine alan adı gönderilir, tam dosya URL'si gönderilmez.

## Hız ölçümü

- IPv4/IPv6 adayları dönüşümlü sıralanır, keşif sırasındaki ilk 16 aday seçilir.
- Varsayılan: 3 tur, örnek başına 4 MiB, istek başına 6 saniye, bağlantı için 2 saniye. Her turda aday sırası döner ve aynı dosyanın sonraki bölümü kullanılır.
- Varsayılan hız testi bütçesi en fazla 192 MiB gövde verisidir. Küçük URL kontrolleri ve protokol trafiği buna eklenir. Başarısız denemeler de veri tüketir.
- curl ayar dosyası, yönlendirme takibi ve proxy kullanımı kapalıdır. HTTPS alan adı ve sertifika doğrulaması açıktır. curl 8.4+, Range yok sayılsa bile gövde boyutunu sınırlar.
- HTTP 206 ve istenen Content-Range gereklidir. Tam örneklerin boyutu eşleşmelidir. Zaman aşımı örnekleri, geçerli TLS ve aralık bilgisiyle en az 256 KiB veri geldiyse kullanılabilir.
- Sonuçlar, bağlantı süresi dahil medyan MB/sn değeridir. Yalnızca tüm turları geçen adresler önerilir. Her adres ailesinden en fazla bir kazanan seçilir.

Bunlar kısa testlerdir, sürekli hız garantisi vermez. `--sample-mib 16` daha büyük örnek indirir ve daha fazla veri tüketir. TLS ve aralık bilgisi doğrulanır; tüm paketin imzası veya farklı sunuculardaki dosyaların bayt bazında eşitliği doğrulanmaz.

## Seçenekler

| Seçenek | Amaç | Varsayılan |
|---|---|---|
| `--lang tr` veya `--lang en` | Dil | en; etkileşimli seçim |
| `--find-url` | Yerel kayıtlardan URL adaylarını listele, çık | kapalı |
| `--url URL` | Belirli Apple dosyasını test et | hazır liste |
| `--discover-only` | Yalnızca DNS; dosya kontrolü/indirme yok | kapalı |
| `--yes` | Etkileşimli soruları atla | kapalı |
| `--rounds 3` | Tur sayısı, 2..5 | 3 |
| `--sample-mib 4` | Örnek başına MiB, 1..16 | 4 |
| `--max-candidates 16` | Aday sınırı, 1..64 | 16 |
| `--timeout 6` | Örnek başına saniye, 2..15 | 6 |
| `--report results.tsv` | Mevcut dosyayı ezmeden TSV raporu kaydet | kaydetmez |
| `--help` | Yardım | |

```bash
bash macos/speedtest.sh --lang tr --discover-only --yes
bash macos/speedtest.sh --lang tr --yes --report results.tsv
```

## Sonucu uygulama ve geri alma

Uygulamak isteğe bağlıdır. Araç hosts, DNS, IPv6 veya sertifika ayarlarını değiştirmez.

1. `/etc/hosts` dosyasını yedekleyin.
2. `sudo nano /etc/hosts` ile açın.
3. Test edilen alan adının eski satırlarını önerilenlerle değiştirin. Aynı alan adı için birden fazla IPv4 veya IPv6 satırı biriktirmeyin.
4. Kaydedip önbelleği yenileyin:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

5. Güncelleme indirme aşamasındayken indirmeyi yeniden başlatın. Hazırlama veya kurulumu kesmeyin.
6. Güncellemeden sonra eklediğiniz satırları kaldırıp önbelleği tekrar yenileyin.

Bir adres ailesinde kazanan bulunamazsa indirici o ailenin normal DNS yolunu kullanabilir. Araç IPv6'yı kapatmaz. Açık bağlantılar eski hedefi kullanmaya devam edebilir.

Apple ile bağlantısı olmayan bağımsız bir araçtır. IP'ler değişebilir; aynı anycast IP farklı fiziksel sunuculara ulaşabilir. Betik telemetri göndermez.
