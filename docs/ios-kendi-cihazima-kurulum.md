# iPhone'uma Nasıl Kurarım (Mac'im Yokken)

Bu rehber, Fedora üzerinde geliştirilen bu fork'un kendi iPhone'una kurulması içindir.
Derleme işini GitHub Actions'ın macOS runner'ı yapıyor, dolayısıyla **Mac'e ihtiyacın yok**.

---

## Önce şunu bil: ücretsiz Apple ID yetmiyor

Uygulama şu yetkilendirmeleri kullanıyor ve ücretsiz "personal team" hesapları bunların
hiçbirini imzalayamıyor:

| Yetkilendirme | Kullanan | Ücretsiz hesap |
|---|---|---|
| App Groups | Widget'lar, Watch uygulaması, Share extension | ❌ |
| HealthKit + background delivery | Ana uygulama (çekirdek özellik) | ❌ |
| Associated domains | Ana uygulama | ❌ |

AltStore / SideStore ile ücretsiz sideload yapmak için widget'ları, Watch uygulamasını,
Share extension'ı ve HealthKit'i **sökmen** gerekirdi. Geriye uygulamanın kabuğu kalırdı
ve profil 7 günde bir yenilenmek zorunda olurdu.

**Sonuç: Apple Developer Program ($99/yıl) kritik yol üzerinde. Mac değil.**

---

## Toplam maliyet ve süre

| | |
|---|---|
| Para | $99 / yıl (Apple Developer Program) |
| İlk kurulum | ~2–4 saat (çoğu Apple'ın onay beklemesi) |
| Sonraki her build | Otomatik — push'la, telefonuna TestFlight'tan düşer |

---

## Adım 1 — Apple Developer Program üyeliği

1. https://developer.apple.com/programs/enroll/ adresine git.
2. Bireysel (Individual) olarak kaydol. Şirket açmana gerek yok.
3. Kimlik doğrulama 24–48 saat sürebilir. Bu süre boyunca diğer adımları yapamazsın,
   sabırla bekle.

Üyelik onaylanınca **Team ID**'ni not et:
https://developer.apple.com/account → Membership details → Team ID (10 karakter, örn. `A1B2C3D4E5`)

---

## Adım 2 — Kod değişikliği: kendi kimliğine geç

Şu an tüm bundle ID'ler `com.apoorvdarshan.*` — yani orijinal geliştiricinin kimliği.
Bunları Apple'a kendi adına kaydedemezsin, çakışır. Kendi ters-DNS önekine geçmen gerekiyor.

Değişmesi gerekenler (**hepsi tek dosyada**: `ios/calorietracker.xcodeproj/project.pbxproj`):

**Bundle ID'ler (5 üretim + 5 debug):**

```
com.apoorvdarshan.calorietracker                        → com.SENIN.calorietracker
com.apoorvdarshan.calorietracker.calorietrackerShare    → com.SENIN.calorietracker.calorietrackerShare
com.apoorvdarshan.calorietracker.FudAIWidgets           → com.SENIN.calorietracker.FudAIWidgets
com.apoorvdarshan.calorietracker.watch                  → com.SENIN.calorietracker.watch
com.apoorvdarshan.calorietracker.watch.FudAIWatchWidgets → com.SENIN.calorietracker.watch.FudAIWatchWidgets
```

**App Group (`APP_GROUP_IDENTIFIER` build setting'i, 2 değer):**

```
group.com.apoorvdarshan.calorietracker        → group.com.SENIN.calorietracker
group.com.apoorvdarshan.calorietracker.debug  → group.com.SENIN.calorietracker.debug
```

> **İyi haber:** App Group ismi projede tek bir build setting olarak tanımlı ve
> `INFOPLIST_KEY_AppGroupIdentifier` üzerinden Swift'e geçiyor. Yani Swift dosyalarını
> tek tek düzenlemene gerek yok — `WidgetSnapshot.swift` içindeki sabitler yalnızca
> yedek (fallback) ve build setting doluyken hiç kullanılmıyor.

Fedora'da tek komutla (`SENIN` yerine kendi önekini yaz — örn. `ifrankerem`):

```bash
cd ~/Desktop/fud-ai
sed -i 's/com\.apoorvdarshan\.calorietracker/com.SENIN.calorietracker/g' \
  ios/calorietracker.xcodeproj/project.pbxproj
```

Sonra doğrula:

```bash
grep -o "PRODUCT_BUNDLE_IDENTIFIER = [^;]*" ios/calorietracker.xcodeproj/project.pbxproj | sort -u
grep -o "APP_GROUP_IDENTIFIER = [^;]*" ios/calorietracker.xcodeproj/project.pbxproj | sort -u
```

Test hedeflerinin (`calorietrackerTests`, `calorietrackerUITests`) bundle ID'leri de
değişecek — sorun değil, onlar Apple'a kaydedilmiyor.

### Associated domains'i kaldır

`ios/calorietracker/calorietracker.entitlements` içinde `applinks:www.fud-ai.app` var.
Bu alan senin değil, çalışmayacak. Şu bloğu sil:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:www.fud-ai.app</string>
</array>
```

Böylece portal'da bir yetkilendirme daha ayarlamaktan kurtulursun.

---

## Adım 3 — Apple Developer portal kayıtları

https://developer.apple.com/account/resources

### 3a. App Group

**Identifiers → + → App Groups**

- Identifier: `group.com.SENIN.calorietracker`
- Description: `Fud AI Shared`

Debug için ikinci bir tane (`group.com.SENIN.calorietracker.debug`) şart değil —
TestFlight build'i Release konfigürasyonunda çıkar.

### 3b. App ID'ler (5 adet)

**Identifiers → + → App IDs → App**

Her biri için Bundle ID'yi **Explicit** olarak gir:

| # | Bundle ID | Açılacak yetenekler |
|---|---|---|
| 1 | `com.SENIN.calorietracker` | **HealthKit**, **App Groups** |
| 2 | `com.SENIN.calorietracker.calorietrackerShare` | App Groups |
| 3 | `com.SENIN.calorietracker.FudAIWidgets` | App Groups |
| 4 | `com.SENIN.calorietracker.watch` | App Groups |
| 5 | `com.SENIN.calorietracker.watch.FudAIWatchWidgets` | App Groups |

App Groups'u açarken **Edit**'e basıp yukarıda oluşturduğun grubu seç. Beş hedefin
de aynı grubu seçmesi gerekiyor — widget ve Watch verisi oradan akıyor.

> HealthKit background delivery ayrı bir kutu değil; HealthKit açıkken entitlement
> dosyasındaki anahtar yeterli.

---

## Adım 4 — Sertifika (Fedora'da, Mac'siz)

Apple'ın "Keychain Access ile CSR üret" talimatı Mac içindir. `openssl` ile aynısını
yapabilirsin.

### 4a. Anahtar ve CSR üret

```bash
mkdir -p ~/fudai-signing && cd ~/fudai-signing

openssl genrsa -out ios_distribution.key 2048

openssl req -new -key ios_distribution.key -out ios_distribution.csr \
  -subj "/emailAddress=SENIN@EPOSTAN/CN=Ad Soyad/C=TR"
```

### 4b. Apple'a yükle

**Certificates → + → Apple Distribution** → `ios_distribution.csr` dosyasını yükle →
`distribution.cer` dosyasını indir.

### 4c. `.p12` paketine dönüştür

```bash
cd ~/fudai-signing

openssl x509 -inform DER -in distribution.cer -out distribution.pem -outform PEM

openssl pkcs12 -export -legacy \
  -inkey ios_distribution.key \
  -in distribution.pem \
  -out distribution.p12 \
  -name "iOS Distribution"
```

Bir parola soracak — **kaydet**, GitHub secret'ı olarak lazım olacak.

> `-legacy` bayrağı önemli. Fedora'daki OpenSSL 3.x varsayılan olarak macOS'un
> okuyamadığı bir şifreleme kullanıyor; bu bayrak olmadan runner `.p12`'yi import
> edemez ve hata mesajı da bunu söylemez.

### 4d. GitHub secret'ı için base64'le

```bash
base64 -w0 distribution.p12 > distribution.p12.b64
cat distribution.p12.b64   # içeriği kopyala
```

> ⚠️ `~/fudai-signing` klasörünü **asla** git'e ekleme. `.key` ve `.p12` dosyaları
> senin imzan; sızarsa senin adına uygulama imzalanabilir.

---

## Adım 5 — Provisioning profile'lar (5 adet)

**Profiles → + → App Store Connect** (Distribution altında)

Her App ID için bir tane, toplam 5. Her birinde:
- App ID: yukarıdaki listeden ilgili olan
- Certificate: az önce oluşturduğun Apple Distribution sertifikası
- İsim: örn. `FudAI AppStore`, `FudAI Widgets AppStore`, ...

Hepsini indir, sonra base64'le:

```bash
cd ~/fudai-signing
for f in *.mobileprovision; do
  echo "=== $f ==="
  base64 -w0 "$f"
  echo
done
```

---

## Adım 6 — App Store Connect

### 6a. Uygulama kaydı

https://appstoreconnect.apple.com → **Apps → +**

- Platform: iOS
- Bundle ID: `com.SENIN.calorietracker`
- SKU: serbest, örn. `fudai-fork-001`

> **Dikkat:** App Store'daki isimler benzersiz olmak zorunda. "Fud AI" muhtemelen
> alınmış. TestFlight için isim önemsiz — `Fud AI (Kero)` gibi bir şey yaz, geç.

### 6b. API anahtarı (yükleme için)

**Users and Access → Integrations → App Store Connect API → Team Keys → +**

- Access: **App Manager**
- Oluştur ve `.p8` dosyasını indir — **yalnızca bir kez indirilebilir**.
- Şu üçünü not et: **Issuer ID**, **Key ID**, `.p8` dosyasının içeriği.

Bu anahtar sayesinde CI, Apple ID parolan veya 2FA kodu olmadan yükleme yapabilir.

---

## Adım 7 — GitHub secret'ları

Fork'unda: **Settings → Secrets and variables → Actions → New repository secret**

| Secret adı | Değer |
|---|---|
| `IOS_TEAM_ID` | Adım 1'deki 10 karakterlik Team ID |
| `IOS_DIST_CERT_P12` | Adım 4d'deki base64 çıktısı |
| `IOS_DIST_CERT_PASSWORD` | Adım 4c'de belirlediğin parola |
| `IOS_PROFILE_APP` | Ana uygulamanın profile'ı (base64) |
| `IOS_PROFILE_SHARE` | Share extension profile'ı (base64) |
| `IOS_PROFILE_WIDGETS` | Widget profile'ı (base64) |
| `IOS_PROFILE_WATCH` | Watch app profile'ı (base64) |
| `IOS_PROFILE_WATCH_WIDGETS` | Watch widget profile'ı (base64) |
| `ASC_KEY_ID` | App Store Connect Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` dosyasının tam içeriği (`-----BEGIN` satırı dahil) |

---

## Adım 8 — Release workflow

**Bu workflow henüz depoda yok.** Mevcut `.github/workflows/ios-ci.yml` yalnızca
simülatör için, imzasız derliyor — bilerek öyle, çünkü sertifika gerektirmemesi
gerekiyordu.

TestFlight'a yükleyen ayrı bir workflow lazım. Kabaca yapacağı iş:

1. Sertifikayı geçici bir keychain'e import et
2. Provisioning profile'ları `~/Library/MobileDevice/Provisioning Profiles/` altına koy
3. `xcodebuild archive` (Release, manuel imzalama)
4. `xcodebuild -exportArchive` ile `.ipa` üret
5. `xcrun altool` veya `xcrun notarytool` ile App Store Connect'e yükle

Secret'ları hazırlayınca haber ver, yazayım. Elle yazmak istersen adımlar yukarıda.

---

## Adım 9 — Telefona kurulum

1. Build App Store Connect'e düştükten sonra **10–30 dakika** işlenir.
2. **TestFlight → Internal Testing** altında kendini tester olarak ekle
   (kendi Apple ID'nle — anında erişim, inceleme beklemez).
3. iPhone'una App Store'dan **TestFlight** uygulamasını kur.
4. Davet e-postasındaki linke tıkla, uygulamayı kur.

Bundan sonra her yeni build otomatik olarak TestFlight'ta belirir.

---

## Uygulamayı kullanmaya başlarken

Kurulum bittikten sonra uygulama içinde:

1. **Ayarlar → AI Provider**'dan bir sağlayıcı seç (Gemini, OpenAI, Claude, Groq...).
2. Kendi **API anahtarını** gir. Anahtar cihazın Keychain'inde saklanır, hiçbir yere
   gönderilmez.
3. HealthKit izinlerini onayla (istersen atlayabilirsin).
4. Bir yemek fotoğrafı çek — yeni iki aşamalı analiz devreye girer: bileşen dökümü,
   kalori aralığı ve gerekirse en fazla üç soru.

---

## Sorun giderme

**"No signing certificate found"** → `.p12` `-legacy` bayrağı olmadan üretilmiş olabilir.
Adım 4c'yi tekrarla.

**"Provisioning profile doesn't match bundle identifier"** → `project.pbxproj`'deki
bundle ID ile portal'daki App ID birebir aynı değil. Adım 2'deki `grep` komutlarıyla
karşılaştır.

**"App Groups capability requires..."** → Beş App ID'nin hepsinde App Groups açık ve
hepsi **aynı** grubu seçmiş olmalı.

**Build "Processing" aşamasında takılırsa** → Genelde 30 dakika içinde geçer. Bir saati
aşarsa Apple'dan e-posta gelir; sebep genelde eksik `Info.plist` anahtarı olur.

**TestFlight'ta build görünmüyor** → App Store Connect'te uygulama kaydının bundle ID'si
yüklenen build'inkiyle aynı mı, kontrol et.

---

## Alternatifler

**Bulut Mac** (Scaleway Mac mini ~€0.10/saat, MacinCloud): tek seferlik iş için ucuz.
Ama imzalama için yine ücretli hesap gerekiyor — Mac sorunu çözüyor, hesap sorununu değil.

**Bir Mac ödünç al:** sertifikayı bir kereliğine üretmek yeterli, bir yıl geçerli.
Yine de sonrasında bu workflow'a ihtiyacın olacak.

**Xcode Cloud:** orijinal proje bunu kullanıyor (bkz. `.github/workflows/ios-release.yml`
yorumları) ve App Store Connect web arayüzünden kurulabilir. Ücretli hesap yine şart;
GitHub Actions zaten kurulu olduğu için oradan devam etmek daha az iş.

---

## Lisans notu

Bu proje MIT lisanslı (© 2026 Apoorv Darshan). Fork'lamak, değiştirmek ve kendi
cihazına kurmak serbest. App Store'da **yayınlamak** istersen telif bildirimini
korumalısın ve uygulamayı kendi ismiyle, orijinalin klonu gibi görünmeyecek şekilde
sunman gerekir. Kişisel kullanım ve TestFlight için bir sorun yok.
