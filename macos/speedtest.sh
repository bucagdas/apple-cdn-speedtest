#!/usr/bin/env bash
set -eu
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LANGUAGE=en
URL=
ROUNDS=3
SAMPLE_MIB=4
MAX_CANDIDATES=16
TIMEOUT=6
YES=0
DISCOVER_ONLY=0
REPORT=
WORK=
FIND_URL=0

say() { if [ "$LANGUAGE" = tr ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
fail() { say "$1" "$2" >&2; exit 1; }
usage() {
    printf '%s\n' 'Apple CDN Speedtest' \
      'bash macos/speedtest.sh [--lang en|tr] [--url HTTPS_URL] [--yes]' \
      '  --rounds 2..5           Repeated samples / Tekrar sayısı' \
      '  --sample-mib 1..16      MiB per sample / Örnek başına MiB' \
      '  --max-candidates 1..64  Candidate limit / Aday sınırı' \
      '  --timeout 2..15        Seconds per sample / Örnek süresi' \
      '  --find-url            Find update URLs in Mac logs / Kayıtlardan URL bul' \
      '  --discover-only       DNS only / Yalnızca DNS' \
      '  --report FILE         Save TSV / TSV kaydet' \
      '  --help'
}
number() {
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ "${#1}" -le 2 ] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0;;
        --yes) YES=1; shift;;
        --find-url) FIND_URL=1; shift;;
        --discover-only) DISCOVER_ONLY=1; shift;;
        --lang|--url|--rounds|--sample-mib|--max-candidates|--timeout|--report)
            [ "$#" -ge 2 ] || { usage >&2; exit 1; }
            case "$1" in
                --lang) LANGUAGE=$2;; --url) URL=$2;; --rounds) ROUNDS=$2;;
                --sample-mib) SAMPLE_MIB=$2;; --max-candidates) MAX_CANDIDATES=$2;;
                --timeout) TIMEOUT=$2;; --report) REPORT=$2;;
            esac
            shift 2;;
        *) usage >&2; exit 1;;
    esac
done
if [ -t 0 ] && [ "$#" -eq 0 ] && [ "$YES" -eq 0 ]; then
    printf 'Language / Dil [en/tr] (%s): ' "$LANGUAGE"
    read -r choice
    [ -z "$choice" ] || LANGUAGE=$choice
fi
case "$LANGUAGE" in en|tr) ;; *) fail 'Language must be en or tr.' 'Dil en veya tr olmalı.';; esac
if [ "$FIND_URL" -eq 1 ]; then
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    say 'Reading the last hour of update logs. Keep an update downloading.' 'Son bir saatin güncelleme kayıtları okunuyor. Güncelleme indiriliyor olmalı.' >&2
    if ! /usr/bin/log show --last 1h --style compact \
        --predicate 'process == "softwareupdated" AND eventMessage CONTAINS[c] "https://"' > "$WORK/log" 2> "$WORK/error"; then
        fail 'Cannot read update logs. Check Terminal permissions; see README.' 'Güncelleme kayıtları okunamadı. Terminal izinlerini ve kullanım belgesini kontrol edin.'
    fi
    grep -Eo 'https://(updates\.cdn-apple\.com|swcdn\.apple\.com)/[^ "<>\\]+' "$WORK/log" |
        grep -E '\.(zip|pkg)(\?.*)?$' | grep -vE 'Documentation|MacUpdateBrain' | sort -u > "$WORK/urls"
    if [ ! -s "$WORK/urls" ]; then
        fail 'No payload URL found. Logs may be redacted. Start a download and retry, or use bundled URLs.' 'Dosya URL bulunamadı. Kayıtlar gizlenmiş olabilir. İndirmeyi başlatıp tekrar deneyin veya hazır adresleri kullanın.'
    fi
    cat "$WORK/urls"
    say 'Use the matching large update URL with --url. These are candidates, not a detected current version.' 'İlgili büyük güncellemenin URL adresini --url ile kullanın. Bunlar aday adreslerdir; güncel sürüm otomatik belirlenmez.' >&2
    exit 0
fi
number "$ROUNDS" 2 5 && number "$SAMPLE_MIB" 1 16 && number "$MAX_CANDIDATES" 1 64 && number "$TIMEOUT" 2 15 ||
    fail 'Invalid numeric option. See --help.' 'Geçersiz sayısal seçenek. --help ile bakabilirsiniz.'
for tool in dig curl awk sort mktemp; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool. See README." "Eksik araç: $tool. README.tr.md dosyasına bakın."
done
validate_url() {
    case "$1" in
        https://updates.cdn-apple.com/?*) HOST=updates.cdn-apple.com;;
        https://swcdn.apple.com/?*) HOST=swcdn.apple.com;;
        *) return 1;;
    esac
    case "$1" in *[[:space:]]*|*'#'*) return 1;; esac
}
VERSION=$(curl --disable --version | awk 'NR==1 {print $2}')
awk -v v="$VERSION" 'BEGIN {split(v,a,"."); exit !(a[1]>8 || (a[1]==8 && a[2]>=4))}' ||
    fail 'curl 8.4+ is required for a transfer size limit. Update curl first.' 'Aktarım boyutu sınırı için curl 8.4+ gerekli. Önce curl aracını güncelleyin.'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$URL" ]; then
    validate_url "$URL" || fail 'Invalid Apple HTTPS file URL.' 'Geçersiz Apple HTTPS dosya adresi.'
    printf '%s\n' "$URL" > "$WORK/urls"
else
    awk 'NF && $0 !~ /^#/ {sub(/\r$/, ""); print}' "$ROOT/config/test-urls.txt" > "$WORK/urls"
fi
if [ "$DISCOVER_ONLY" -eq 1 ]; then
    URL=$(head -n 1 "$WORK/urls")
    validate_url "$URL" || fail 'Invalid configured URL.' 'Yapılandırmadaki URL geçersiz.'
else
    say 'Checking test URLs with one-byte requests before speed tests...' 'Hız testinden önce adresler bir baytlık isteklerle kontrol ediliyor...'
    while :; do
        selected_url=
        while IFS= read -r candidate_url; do
            validate_url "$candidate_url" || continue
            code=0
            status=$(curl --disable --silent --globoff --noproxy '*' --proto '=https' \
                --http1.1 --range 0-0 --max-filesize 1 --max-time 5 --connect-timeout 2 \
                --dump-header "$WORK/probe" --output /dev/null --write-out '%{http_code} %{size_download} %{ssl_verify_result}' \
                "$candidate_url" 2>/dev/null) || code=$?
            total=$(awk 'tolower($1)=="content-range:" {gsub("\r", ""); if($2=="bytes" && $3 ~ /^0-0\/[0-9]+$/){split($3,a,"/");print a[2]}}' "$WORK/probe" 2>/dev/null | tail -n 1)
            if [ "$code" -eq 0 ] && [ "$status" = '206 1 0' ] && \
                awk -v n="$total" -v required="$((ROUNDS * SAMPLE_MIB * 1048576))" 'BEGIN {exit !(n ~ /^[0-9]+$/ && n>=required)}'; then
                selected_url=$candidate_url
                break
            fi
            say "Unavailable or too small: $candidate_url" "Erişilemedi veya dosya çok küçük: $candidate_url"
        done < "$WORK/urls"
        if [ -n "$selected_url" ]; then URL=$selected_url; validate_url "$URL"; break; fi
        say 'No usable test URL. This can also be a network problem. Run --find-url or download an updated copy of this project.' \
            'Kullanılabilir test URL bulunamadı. Ağ sorunu da olabilir. --find-url çalıştırın veya projenin güncel kopyasını indirin.'
        if [ "$YES" -eq 1 ] || [ ! -t 0 ]; then exit 1; fi
        say 'Paste another Apple HTTPS file URL, or press Enter to exit:' 'Başka bir Apple HTTPS dosya adresi yapıştırın; çıkmak için Enter:'
        read -r replacement_url
        [ -n "$replacement_url" ] || exit 1
        validate_url "$replacement_url" || fail 'Invalid Apple HTTPS file URL.' 'Geçersiz Apple HTTPS dosya adresi.'
        printf '%s\n' "$replacement_url" > "$WORK/urls"
    done
fi
: > "$WORK/raw"
say 'Discovering IPv4/IPv6 via system DNS and public resolvers...' 'Sistem DNS ve halka açık DNS ile IPv4/IPv6 adresleri bulunuyor...'
discover() {
    local provider=$1 server=$2 kind answer
    for kind in A AAAA; do
        if [ -n "$server" ]; then
            answer=$(dig "@$server" "$HOST" "$kind" +noall +answer +time=2 +tries=1 2>/dev/null) || answer=
        else
            answer=$(dig "$HOST" "$kind" +noall +answer +time=2 +tries=1 2>/dev/null) || answer=
        fi
        printf '%s\n' "$answer" | awk -v source="$provider" \
          '$4=="A" && $5 ~ /^[0-9.]+$/ {print $5 "\tIPv4\t" source}
           $4=="AAAA" && $5 ~ /^[0-9a-fA-F:]+$/ {print tolower($5) "\tIPv6\t" source}' >> "$WORK/raw"
    done
}
discover System ''
while read -r provider server extra; do
    case "$provider" in ''|'#'*) continue;; esac
    discover "$provider" "$server"
done < "$ROOT/config/resolvers.txt"
awk -F '\t' '!seen[$1]++' "$WORK/raw" > "$WORK/all"
[ -s "$WORK/all" ] || fail 'No DNS candidates found. Check network/DNS access.' 'DNS adayı bulunamadı. Ağ ve DNS erişimini kontrol edin.'
cat "$WORK/all"
COUNT=$(awk 'END {print NR}' "$WORK/all")
if [ "$DISCOVER_ONLY" -eq 1 ]; then exit 0; fi
# Interleave families before applying the cap.
awk -F '\t' '$2=="IPv4" {a[++n]=$0} $2=="IPv6" {b[++m]=$0}
    END {for(i=1;i<=n || i<=m;i++){if(i<=n)print a[i];if(i<=m)print b[i]}}' "$WORK/all" |
    head -n "$MAX_CANDIDATES" > "$WORK/candidates"
SELECTED=$(awk 'END {print NR}' "$WORK/candidates")
BYTES=$((SAMPLE_MIB * 1048576))
BUDGET=$((SELECTED * ROUNDS * SAMPLE_MIB))
say "Testing $SELECTED of $COUNT IPs. Up to $BUDGET MiB of body data, plus protocol overhead." \
    "$COUNT IP içinden $SELECTED aday test edilecek. En fazla $BUDGET MiB gövde verisi ve protokol trafiği."
say 'Public DNS providers receive the hostname. Direct tests bypass proxies. No system settings change.' \
    'Halka açık DNS servislerine alan adı gönderilir. Testler proxy kullanmaz. Sistem ayarları değişmez.'
say "Test file: $URL" "Test dosyası: $URL"
if [ "$YES" -ne 1 ]; then
    [ -t 0 ] || fail 'Use --yes for non-interactive tests.' 'Etkileşimsiz test için --yes kullanın.'
    say 'Start? [y/N]' 'Başlatılsın mı? [e/H]'
    read -r answer
    case "$answer" in y|Y|e|E) ;; *) exit 0;; esac
fi
: > "$WORK/samples"
round=1
while [ "$round" -le "$ROUNDS" ]; do
    start=$(((round - 1) * BYTES))
    end=$((start + BYTES - 1))
    # Rotate order to reduce first-server bias.
    awk -v r="$round" '{a[NR]=$0} END {for(i=0;i<NR;i++)print a[(i+r-1)%NR+1]}' "$WORK/candidates" > "$WORK/order"
    while IFS="$(printf '\t')" read -r ip family source; do
        address=$ip
        [ "$family" != IPv6 ] || address="[$ip]"
        rc=0
        metrics=$(curl --disable --silent --show-error --globoff --noproxy '*' --proto '=https' \
            --http1.1 --resolve "$HOST:443:$address" --range "$start-$end" \
            --max-filesize "$BYTES" --max-time "$TIMEOUT" --connect-timeout 2 \
            --dump-header "$WORK/headers" --output /dev/null \
            --write-out '%{http_code} %{size_download} %{time_total} %{ssl_verify_result}' \
            "$URL" 2> "$WORK/error") || rc=$?
        range=$(awk 'tolower($1)=="content-range:" {gsub("\r", ""); print $2 " " $3}' "$WORK/headers" 2>/dev/null | tail -n 1)
        speed=$(printf '%s\n' "$metrics" | awk -v rc="$rc" -v range="$range" -v wanted="bytes $start-$end/" -v cap="$BYTES" '
            NF==4 && (rc==0 || rc==28) && $1==206 && $2>=262144 && $2<=cap && $3>0 && $4==0 && index(range,wanted)==1 && (rc!=0 || $2==cap) {printf "%.6f", $2/$3/1000000}')
        if [ -n "$speed" ]; then
            printf '%s\t%s\t%s\t%s\n' "$ip" "$family" "$source" "$speed" >> "$WORK/samples"
            printf '[%s/%s] %-40s %s MB/s\n' "$round" "$ROUNDS" "$ip" "$speed"
        else
            say "[$round/$ROUNDS] $ip failed (curl=$rc, HTTP=${metrics%% *})." \
                "[$round/$ROUNDS] $ip başarısız (curl=$rc, HTTP=${metrics%% *})."
        fi
    done < "$WORK/order"
    round=$((round + 1))
done
printf 'IP\tFamily\tFirst_DNS\tMedian_MBps\tSuccessful_samples\n' > "$WORK/report"
sort -t "$(printf '\t')" -k1,1 -k4,4n "$WORK/samples" | awk -F '\t' -v required="$ROUNDS" '
    function emit() {if(n){mid=int((n+1)/2);med=(n%2)?v[mid]:(v[mid]+v[mid+1])/2;printf "%s\t%s\t%s\t%.3f\t%d/%d\n",ip,fam,src,med,n,required}}
    $1!=ip {emit();n=0;ip=$1;fam=$2;src=$3} {v[++n]=$4} END {emit()}' |
    sort -t "$(printf '\t')" -k4,4nr >> "$WORK/report"
say 'Results (MB/s, including connection time):' 'Sonuçlar (MB/sn, bağlantı süresi dahil):'
cat "$WORK/report"
if [ -n "$REPORT" ]; then
    [ ! -e "$REPORT" ] || fail 'Report already exists; choose a new path.' 'Rapor zaten var; yeni bir yol seçin.'
    (set -C; cat "$WORK/report" > "$REPORT")
fi
say 'Optional hosts lines (only candidates passing every round):' 'İsteğe bağlı hosts satırları (tüm turları geçen adaylar):'
awk -F '\t' -v rounds="$ROUNDS" -v host="$HOST" 'NR>1 && $5==rounds "/" rounds && !seen[$2]++ {print $1 " " host; found=1} END {if(!found)exit 1}' "$WORK/report" || {
    fail 'No fully verified candidate. Try another file URL or network; do not use failed IPs.' 'Tüm testleri geçen aday yok. Başka dosya URL veya ağ deneyin; başarısız IP kullanmayın.'
}
say 'Hosts: /etc/hosts. Replace old entries for this hostname, then restart the download. Remove these entries after updating.' \
    'Hosts: /etc/hosts. Bu alan adının eski kayıtlarını değiştirin ve indirmeyi yeniden başlatın. Güncellemeden sonra kayıtları kaldırın.'
say 'If one family has no winner, the downloader may still use its normal DNS route. Short tests do not guarantee sustained speed.' \
    'Bir adres ailesinde kazanan yoksa indirici normal DNS yolunu kullanabilir. Kısa testler sürekli hız garantisi vermez.'
