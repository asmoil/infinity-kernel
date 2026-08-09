#!/system/bin/sh
##########################################################################################
# Infinity Kernel - Userspace Task Detection Helper
# Runs as a service (post-fs-data.d) and detects foreground app category
# Writes a hint to /sys/kernel/infinity_task_engine/userspace_hint
#
# Profile mapping:
#   0 = IDLE
#   1 = SOCIAL  (Telegram, Instagram, Twitter, Facebook, Discord, etc.)
#   2 = BROWSE  (Chrome, Firefox, Brave, Edge, Samsung Internet, etc.)
#   3 = MEDIA   (YouTube, VLC, Spotify, Netflix, Twitch, etc.)
#   4 = NORMAL  (Settings, Launcher, etc.)
#   5 = IO_HEAVY (Play Store installing, file manager copy, etc.)
#   6 = GAMING_LIGHT  (2D games, emulators, simple games)
#   7 = GAMING_HEAVY  (3D heavy games: PUBG, Genshin, CoD, etc.)
#   8 = CHARGING
#
# The kernel engine combines this hint with its own CPU/GPU monitoring
# to make the final profile decision.
##########################################################################################

TASK_ENGINE_SYSFS="/sys/kernel/infinity_task_engine"
INFINITY_LOG="/data/adb/infinity_kernel/task_engine.log"
CONF="/data/adb/infinity_kernel/task_profiles.conf"

log_te() {
    echo "[$(date '+%H:%M:%S')] [TaskEngine] $1" >> "$INFINITY_LOG"
}

# ---- Load custom profile overrides ----
# Users can create /data/adb/infinity_kernel/task_profiles.conf
# Format: com.example.game=7
declare -A CUSTOM_PROFILES
if [ -f "$CONF" ]; then
    while IFS='=' read -r pkg profile; do
        case "$pkg" in
            \#*|"") continue ;;  # Skip comments and empty lines
        esac
        CUSTOM_PROFILES["$pkg"]="$profile"
    done < "$CONF"
    log_te "Loaded custom profiles: $(wc -l < "$CONF") entries"
fi

# ---- Package-to-profile classification ----

# Heavy 3D games — GAMING_HEAVY (7)
HEAVY_GAMES=(
    "com.tencent.ig"           # PUBG Mobile
    "com.epicgames.ue4"        # Epic Games
    "com.miHoYo.GenshinImpact" # Genshin Impact
    "com.activision.callofduty.shooter"  # CoD Mobile
    "com.ea.gp.fifamobile"     # FIFA Mobile
    "com.riotgames.league.wildrift"  # Wild Rift
    "com.garena.freefire"      # Free Fire
    "com.riotgames.teamfighttactics"  # TFT
    "com.pubg.imobile"         # PUBG Mobile (alt)
    "com.krafton.launcher"     # Krafton games
    "com.miHoYo.HoYoverse"     # HoYoverse games
    "com.squareenixmontreal.DFFNT"  # Dissidia
    "com.netease.sky"          # Sky: Children of the Light
    "com.bandainamcoent.tekkenmobile"  # Tekken
    "com.ea.games.r3_row"      # Real Racing 3
    "com.gameloft.android.ANMP.GloftA8HM"  # Asphalt 9
    "com.rockstargames.gtasa"  # GTA SA
    "com.mojang.minecraftpe"   # Minecraft (heavy with shaders)
    "com.ubisoft.mightyquest"  # Ubisoft games
    "com.nexon.bluearchive"    # Blue Archive
)

# Light/casual games — GAMING_LIGHT (6)
LIGHT_GAMES=(
    "com.kiloo.subwaysurf"     # Subway Surfers
    "com.robocraftx.robocraft" # Robocraft
    "com.voodoo.slitherio"     # Slither.io
    "com.outfit7.talkingtom"   # Talking Tom
    "com.miniclip.plagueinc"   # Plague Inc
    "com.fingersoft.hillclimb" # Hill Climb Racing
    "com.zeptolab.ctr2"        # Cut the Rope
    "com.king.candycrushsaga"  # Candy Crush
    "com.chillingo.plantsvszombies2"  # PvZ 2
    "com.disney.pokemon"       # Pokemon GO
    "com.nianticlabs.pokemongo" # Pokemon GO
    "com.mojang.minecraftpe"   # Minecraft (can be both)
    "com.fiveonenine.township" # Township
    "com.playrix.township"     # Township
    "com.king.farmheroessaga"  # Farm Heroes
)

# Social apps — SOCIAL (1)
SOCIAL_APPS=(
    "org.telegram.messenger"   # Telegram
    "org.telegram.messenger.beta"
    "com.instagram.android"    # Instagram
    "com.twitter.android"      # Twitter/X
    "com.facebook.katana"      # Facebook
    "com.facebook.lite"        # Facebook Lite
    "com.facebook.orca"        # Facebook Messenger
    "com.whatsapp"             # WhatsApp
    "com.discord"              # Discord
    "com.snapchat.android"     # Snapchat
    "com.linkedin.android"     # LinkedIn
    "com.reddit.frontpage"     # Reddit
    "com.viber.voip"           # Viber
    "org.thoughtcrime.securesms"  # Signal
    "com.zhiliaoapp.musically" # TikTok
    "com.ss.android.ugc.trill" # TikTok (alt)
)

# Media apps — MEDIA (3)
MEDIA_APPS=(
    "com.google.android.youtube"          # YouTube
    "com.google.android.apps.youtube.music" # YT Music
    "com.google.android.youtube.tv"       # YouTube TV
    "com.vlc.android"                     # VLC
    "com.spotify.music"                   # Spotify
    "com.netflix.mediaclient"             # Netflix
    "com.amazon.mshop.android.shopping"    # Prime Video
    "com.amazon.avod.thirdpartyclient"     # Prime Video (alt)
    "tv.twitch.android.app"               # Twitch
    "com.google.android.videos"           # Google TV
    "com.apple.android.music"             # Apple Music
    "com.deezer.android"                  # Deezer
    "com.soundcloud.android"              # SoundCloud
    "org.videolan.vlc"                    # VLC (alt)
    "com.mxtech.videoplayer.ad"           # MX Player
    "com.mxtech.videoplayer.pro"          # MX Player Pro
    "is.xyz.mpv"                          # mpv
)

# Browser apps — BROWSE (2)
BROWSE_APPS=(
    "com.android.chrome"                  # Chrome
    "com.chrome.beta"                     # Chrome Beta
    "com.android.browser"                 # AOSP Browser
    "org.mozilla.firefox"                 # Firefox
    "org.mozilla.fennec_fdroid"           # Firefox F-Droid
    "com.brave.browser"                   # Brave
    "com.microsoft.emmx"                  # Edge
    "com.opera.browser"                   # Opera
    "com.opera.mini.native"               # Opera Mini
    "com.sec.android.app.sbrowser"        # Samsung Internet
    "com.ecosia.android"                  # Ecosia
    "com.duckduckgo.android.browser"      # DuckDuckGo
    "org.torproject.torbrowser"           # Tor
    "com.vivaldi.browser"                 # Vivaldi
)

# ---- Get current foreground package ----
get_foreground_package() {
    # Method 1: dumpsys activity (most reliable)
    local pkg
    pkg=$(dumpsys activity recents 2>/dev/null | \
        grep -m1 "Recent #0" | \
        sed 's/.*#0:.*\(com\.\|org\.\|net\.\|io\.\|me\.\)[^ ]* .*/\1/' 2>/dev/null)

    if [ -z "$pkg" ] || [ "$pkg" = "" ]; then
        # Method 2: cmd activity
        pkg=$(cmd activity get-foreground-activity 2>/dev/null | \
            grep -oP '(com\.|org\.|net\.|io\.|me\.)[a-zA-Z0-9_.]+' | head -1)
    fi

    if [ -z "$pkg" ]; then
        # Method 3: check running processes
        pkg=$(dumpsys activity activities 2>/dev/null | \
            grep -m1 "mResumedActivity" | \
            grep -oP '(com\.|org\.|net\.|io\.|me\.)[a-zA-Z0-9_.]+' | head -1)
    fi

    echo "$pkg"
}

# ---- Classify package ----
classify_package() {
    local pkg="$1"
    local i

    # Check custom overrides first
    if [ -n "${CUSTOM_PROFILES[$pkg]}" ]; then
        echo "${CUSTOM_PROFILES[$pkg]}"
        return
    fi

    # Check heavy games
    for i in "${HEAVY_GAMES[@]}"; do
        if [ "$pkg" = "$i" ]; then echo 7; return; fi
    done

    # Check light games
    for i in "${LIGHT_GAMES[@]}"; do
        if [ "$pkg" = "$i" ]; then echo 6; return; fi
    done

    # Check social
    for i in "${SOCIAL_APPS[@]}"; do
        if [ "$pkg" = "$i" ]; then echo 1; return; fi
    done

    # Check media
    for i in "${MEDIA_APPS[@]}"; do
        if [ "$pkg" = "$i" ]; then echo 3; return; fi
    done

    # Check browsers
    for i in "${BROWSE_APPS[@]}"; do
        if [ "$pkg" = "$i" ]; then echo 2; return; fi
    done

    # Unknown app = NORMAL (4)
    echo 4
}

# ---- Check if screen is on ----
is_screen_on() {
    local power_state
    power_state=$(dumpsys power 2>/dev/null | grep "mWakefulness" | \
        head -1 | awk '{print $2}')
    [ "$power_state" = "Awake" ] || [ "$power_state" = "Dreaming" ]
}

# ---- Check if charging ----
is_charging() {
    local status
    status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    [ "$status" = "Charging" ] || [ "$status" = "Full" ]
}

# ---- Check if Play Store is installing ----
is_installing() {
    # Check if package installer is active and doing IO
    local installer_pid
    installer_pid=$(pidof com.android.packageinstaller 2>/dev/null)
    if [ -n "$installer_pid" ]; then
        # Check CPU usage of installer
        local cpu_usage
        cpu_usage=$(top -b -n 1 -p "$installer_pid" 2>/dev/null | \
            tail -1 | awk '{print $9}' | cut -d'.' -f1)
        if [ -n "$cpu_usage" ] && [ "$cpu_usage" -gt 10 ] 2>/dev/null; then
            return 0  # Yes, installing
        fi
    fi
    return 1
}

# ===================================================================
# MAIN LOOP
# ===================================================================

log_te "=== Task Engine Userspace Helper Starting ==="

# Wait for system to fully boot
sleep 30

# Verify sysfs exists
if [ ! -d "$TASK_ENGINE_SYSFS" ]; then
    log_te "ERROR: Task engine sysfs not found at $TASK_ENGINE_SYSFS"
    log_te "Kernel module may not be loaded. Exiting."
    exit 1
fi

# Enable auto-detect
echo "1" > "$TASK_ENGINE_SYSFS/auto_detect" 2>/dev/null
log_te "Auto-detection enabled"

# Set detection interval (3 seconds)
echo "3000" > "$TASK_ENGINE_SYSFS/detect_interval" 2>/dev/null
log_te "Detection interval: 3000ms"

# Tell kernel screen is on initially
echo "1" > "$TASK_ENGINE_SYSFS/screen_on" 2>/dev/null

LAST_PACKAGE=""
LAST_HINT=-1
LOOP_COUNT=0

while true; do
    # Check screen state
    if is_screen_on; then
        echo "1" > "$TASK_ENGINE_SYSFS/screen_on" 2>/dev/null
    else
        echo "0" > "$TASK_ENGINE_SYSFS/screen_on" 2>/dev/null
        # Screen off — let kernel handle idle detection
        echo "-1" > "$TASK_ENGINE_SYSFS/userspace_hint" 2>/dev/null
        LAST_PACKAGE=""
        sleep 5
        continue
    fi

    # Check if installing something
    if is_installing; then
        if [ "$LAST_HINT" != "5" ]; then
            echo "5" > "$TASK_ENGINE_SYSFS/userspace_hint" 2>/dev/null
            log_te "Hint: IO_HEAVY (app installing)"
            LAST_HINT=5
        fi
        sleep 3
        continue
    fi

    # Get foreground app
    CURRENT_PACKAGE=$(get_foreground_package)

    # Only reclassify if foreground app changed
    if [ "$CURRENT_PACKAGE" != "$LAST_PACKAGE" ] && [ -n "$CURRENT_PACKAGE" ]; then
        NEW_HINT=$(classify_package "$CURRENT_PACKAGE")

        if [ "$NEW_HINT" != "$LAST_HINT" ]; then
            # Write hint to kernel
            echo "$NEW_HINT" > "$TASK_ENGINE_SYSFS/userspace_hint" 2>/dev/null

            # Read back current profile
            CURRENT_PROFILE=$(cat "$TASK_ENGINE_SYSFS/current_profile" 2>/dev/null)
            log_te "App: $CURRENT_PACKAGE -> Hint: $NEW_HINT -> Profile: $CURRENT_PROFILE"

            LAST_HINT=$NEW_HINT
        fi

        LAST_PACKAGE="$CURRENT_PACKAGE"
    fi

    # If charging and idle, suggest charging profile
    if is_charging && [ "$LAST_HINT" = "4" ]; then
        # Don't override, kernel will decide based on thermal
        :
    fi

    # Log stats every 60 cycles (~3 minutes)
    LOOP_COUNT=$((LOOP_COUNT + 1))
    if [ $((LOOP_COUNT % 60)) -eq 0 ]; then
        log_te "--- Stats dump ---"
        cat "$TASK_ENGINE_SYSFS/stats" >> "$INFINITY_LOG" 2>/dev/null
    fi

    sleep 3
done