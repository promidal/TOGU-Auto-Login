# Auto-Login (PortalKeepalive)

GOP Üniversitesi (TOGÜ) captive portal'ı (https://denetim.gop.edu.tr/) için otomatik giriş + oturum canlı
tutma. Kullanıcıyla Türkçe konuş. GitHub: `promidal/TOGU-Auto-Login` (public). Klasör Google Drive ile
Windows ve Mac arasında senkronize ediliyor (Windows yolu: `G:\Drive'ım\Documents\SERKAN EVRAKLAR\GOP Üniversitesi\Projeler\Auto-Login`).

## Yapı
- `Windows taslağı/` — PowerShell + Task Scheduler + Inno Setup yükleyici
  - `PortalKeepalive.ps1` (ana mantık; modlar: `keepalive`, `login`, `notify`)
  - `Install-PortalKeepalive.ps1`, `Uninstall-PortalKeepalive.ps1`, `PortalKeepalive.iss`
  - Görevler (v1.0.6+): `PortalKeepalive` = SYSTEM, açılışta + her dakika (oturum açılmasını beklemez, ekran yok);
    `PortalKeepalive-Notify` = her kullanıcının oturum açışında `notify` modu (SYSTEM ekran gösteremez, uyarılar burada)
  - Betik `%ProgramFiles%\PortalKeepalive\` altında (yönetici dışı yazamasın: SYSTEM çalıştırıyor). Yükleyici yönetici
    olarak çalışır (`.iss`'de `runasoriginaluser` yok), betik de yönetici değilse hata verir.
  - Veri: `%ProgramData%\PortalKeepalive\` (Users: değiştirme izni; config.json, pass.enc [DPAPI **LocalMachine**, base64],
    token.txt, portal.log, bad-credentials, bad-credentials-shown, update-pending.json, update-check.json).
    Eski %APPDATA% verisi kurulumda silinir; kullanıcı bilgileri yeniden sorulur.
- `Mac/` — Python 3 (`/usr/bin/python3`) + launchd
  - `portal-keepalive.py` (modlar: `keepalive`, `login`), `install.sh`, `uninstall.sh`,
    `com.serkan.portal-keepalive.plist` (şablon, `__HOME__` yer tutucusu install.sh'de sed ile dolar)
  - Kurulunca: `~/.portal-keepalive.py`, `~/.portal-keepalive.json` (kullanıcı adı), Anahtar Zinciri servis
    `PortalKeepalive` (parola), `~/.portal-token`, `~/portal-keepalive.log`, `~/.portal-bad-credentials`,
    `~/.portal-update-check.json`, `~/Applications/PortalKeepalive/{Şifreyi Değiştir,Kaldır}.command`
  - Eski kurulum düz metin `~/.portal.env` (PORTAL_USER/PORTAL_PASS) kullanıyordu; `login` modu bunu
    Anahtar Zinciri'ne taşıyıp siliyor, okuma tarafı hâlâ fallback olarak destekliyor.
- `.github/workflows/build-windows.yml` — main'e her push'ta Windows yükleyiciyi derler (artifact, sürüm "dev")
- `.github/workflows/release-windows.yml` — `v*` etiketi push'unda: Windows `.exe` + (yeni) `PortalKeepalive-Mac.zip`
  release'e yüklenir. Sürüm numarası etiketten alınıp betiklere damgalanır (`$AppVersion = "dev"` /
  `VERSION = "dev"` satırları, `iscc /DAppVer=`). Kaynakta bu satırlar "dev" kalmalı.

## Her iki platformda aynı olması gereken davranışlar
1. Kurulumda kullanıcı adı + parola sorulur, giriş hemen denenir (yanlışsa 3 kez tekrar sorar; kampüs
   dışındaysa kaydedip "kampüse bağlanınca otomatik giriş yapılacak" der).
2. Şifre değiştirme: Windows'ta Başlat menüsü "PortalKeepalive - Şifreyi Değiştir", Mac'te
   `~/Applications/PortalKeepalive/Şifreyi Değiştir.command` → `login` modu (her zaman yeniden sorar).
3. Portal şifreyi reddederse (`Giriş Başarısız` / `Kullanıcı adı / parola hatalı`) bad-credentials işareti
   yazılır, tekrar denenmez (hesap kilitlenme riski), kullanıcıya BİR KEZ uyarı gösterilir (Windows'ta `notify` görevi, `bad-credentials-shown` ile); yeni şifre
   girilince işaret silinir.
4. Güncelleme kontrolü: arka plan görevi günde en fazla 1 kez GitHub `releases/latest`'e bakar
   (anonim limit 60/saat), daha yeni sürüm varsa her sürüm için bir kez "indirme sayfasını aç" uyarısı.
   "dev" sürümde kontrol yapılmaz. Uyarı ayrı süreçte açılır ki keepalive beklemesin (Windows'ta SYSTEM `update-pending.json` yazar, `notify` gösterir).
5. Arka plan görevi asla kullanıcıdan girdi istemez; Windows'ta oturum açılmadan, açılışta çalışır (gizli pencerede Read-Host sonsuza kadar asılı kalırdı).

## Yapılanlar (2026-10-30, Windows makinesinde)
- **v1.0.2 yayınlandı** (commit `8cd3bbe`, sadece Windows): kurulumda şifre sorulmaması hatası düzeltildi
  (AtLogOn tetikleyicisinin `Repetition` nesnesi null → `Repetition.Interval` ataması betiği çökertiyordu;
  `-Once -RepetitionInterval` tetikleyicisinden ödünç alınıyor), şifre değiştirme kısayolu, yanlış şifre
  işareti/uyarısı, güncelleme uyarısı, uninstall betiği pakete eklendi, betikler UTF-8 BOM'lu yapıldı.
  Release workflow başarılı, `PortalKeepalive-Setup.exe` release'te var. Gerçek bir kurulumla HENÜZ test edilmedi.
- **Mac sürümü v1.0.3 ile yayınlandı** (2026-10-30, Mac'te test edildi, macOS 27): install.sh kurulumu,
  Anahtar Zinciri, `~/.portal.env` taşınması, launchd ajanı, tek satır log ve launchd altından `osascript`
  uyarıları (display alert/dialog, -1713 hatası yok) çalıştı. `Kaldır.command` çift tıklamayla denenmedi.
  v1.0.3 etiketi v1.0.2 Windows kullanıcılarına da güncelleme uyarısı gösterir (Windows'ta değişiklik yok).
- **v1.0.4 (2026-11-02, Windows, ilk gerçek kurulumda bulunan hata):** görev hiç oluşmuyordu: kurulum betiği yönetici
  yetkisiz çalışıyor (`runasoriginaluser`), kullanıcısız `-AtLogOn` tetikleyicisi "Erişim engellendi" veriyor, hata da
  yutuluyordu. Ayrıca logon tetikleyicisinin tekrarı ancak sonraki oturum açmada başlıyordu. Artık `-AtLogOn -User` +
  ayrı `-Once` tekrar tetikleyicisi var; görev kaydedilemezse kurulum hata verip duruyor.
- **v1.0.5 (2026-11-02, Windows):** görev ve güncelleme uyarısı `conhost.exe --headless` ile başlıyor (`-WindowStyle
  Hidden` her çalışmada pencere yanıp söndürüyordu). `portal.log` 1 MB'de `portal.log.1`'e dönüyor.

- **v1.0.6 (2026-11-16, Windows):** keepalive artık SYSTEM olarak açılışta başlıyor (eskiden yalnızca oturum açınca);
  veri `%APPDATA%` → `%ProgramData%`, DPAPI LocalMachine kapsamı, `notify` görevi. Gerçek kurulum + yeniden başlatma
  ile HENÜZ test edilmedi. Bilinen sınır: Wi-Fi profili "tüm kullanıcılar" için kayıtlı değilse oturum açılmadan ağa bağlanılmaz.

## Dikkat edilecekler
- Windows `.ps1`/`.iss` dosyaları **UTF-8 BOM'lu** kalmalı (Windows PowerShell 5.1 ve Inno Setup BOM'suz
  dosyadaki Türkçe karakterleri bozuk okur). Mac `.sh` dosyaları **LF** olmalı.
- Repo `core.filemode=true`; Windows'tan çalışınca `Mac/portal-keepalive.py` 755→644 görünüyordu.
  Commit'te `install.sh`, `uninstall.sh`, `portal-keepalive.py` 755 olmalı (`chmod +x` ya da
  `git update-index --chmod=+x`).
- Git kimliği önceki commit'lerdeki gibi: `Serkan Avşar <serkan@Serkan-Mac-mini.local>`.
- `Windows taslağı` klasör adındaki Türkçe karakterler workflow'larda olduğu gibi kullanılıyor; değiştirme.
- Proje kökündeki `SERKAN EVRAKLAR.lnk` kullanıcının kısayolu, repoya ekleme.
