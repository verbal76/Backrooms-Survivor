extends RefCounted
## Platform / device detection for Steam Deck, SteamOS, Steam Machine, Big Picture and Proton.
## Everything here is a cheap static query (results are cached). Reference it with
## `const Platform = preload("res://scripts/platform/platform.gd")` (no class_name, so OTA patch packs keep working).
##
## Signals we rely on (set by Steam / gamescope, all optional):
##   SteamDeck=1                Steam Deck (native and Proton processes both get it)
##   SteamOS=1                  SteamOS session
##   SteamGameId / SteamAppId   launched from the Steam client
##   SteamTenfoot=1             Big Picture / Gaming Mode UI
##   STEAM_COMPAT_DATA_PATH ... Proton (also STEAM_COMPAT_CLIENT_INSTALL_PATH, PROTON_*)
##   /etc/os-release ID=steamos (native Linux on a Deck or Steam Machine)

static var _cache := {}


static func _env(name: String) -> String:
	return OS.get_environment(name)


static func _os_release_is_steamos() -> bool:
	if not FileAccess.file_exists("/etc/os-release"):
		return false
	var txt := FileAccess.get_file_as_string("/etc/os-release").to_lower()
	return txt.contains("id=steamos") or txt.contains("id_like=steamos") or txt.contains("name=\"steamos") \
		or txt.contains("variant_id=steamdeck")


static func is_proton() -> bool:
	if not _cache.has("proton"):
		_cache["proton"] = _env("STEAM_COMPAT_DATA_PATH") != "" or _env("STEAM_COMPAT_CLIENT_INSTALL_PATH") != "" \
			or _env("PROTON_VERSION") != "" or _env("STEAM_COMPAT_APP_ID") != ""
	return _cache["proton"]


static func is_steam_launched() -> bool:
	if not _cache.has("steam"):
		_cache["steam"] = _env("SteamGameId") != "" or _env("SteamAppId") != "" or _env("STEAM_COMPAT_APP_ID") != "" \
			or is_proton()
	return _cache["steam"]


static func is_steamos() -> bool:
	if not _cache.has("steamos"):
		var v := _env("SteamOS")
		_cache["steamos"] = v == "1" or v.to_lower() == "true" \
			or (OS.has_feature("linuxbsd") and _os_release_is_steamos())
	return _cache["steamos"]


## The handheld itself (not a Steam Machine / desktop with Steam).
static func is_steam_deck() -> bool:
	if not _cache.has("deck"):
		var v := _env("SteamDeck")
		var deck := v == "1" or v.to_lower() == "true"
		# native Linux on a Deck without Steam's env (desktop mode, launched by hand): DMI board name
		if not deck and OS.has_feature("linuxbsd") and FileAccess.file_exists("/sys/devices/virtual/dmi/id/product_name"):
			var p := FileAccess.get_file_as_string("/sys/devices/virtual/dmi/id/product_name").strip_edges()
			deck = p == "Jupiter" or p == "Galileo"
		_cache["deck"] = deck
	return _cache["deck"]


## Big Picture / Gaming Mode UI is the front end.
static func is_big_picture() -> bool:
	if not _cache.has("bp"):
		_cache["bp"] = _env("SteamTenfoot") == "1" or _env("SteamGamepadUI") == "1"
	return _cache["bp"]


## True when we should behave like a console-style handheld: controller first, fullscreen, lighter quality.
static func is_deck_like() -> bool:
	return is_steam_deck() or is_big_picture() or (is_steamos() and is_steam_launched())


static func is_desktop() -> bool:
	return not OS.has_feature("mobile") and DisplayServer.get_name() != "headless"


static func describe() -> String:
	var parts: Array[String] = []
	if is_steam_deck():
		parts.append("Steam Deck")
	if is_steamos():
		parts.append("SteamOS")
	if is_proton():
		parts.append("Proton")
	if is_big_picture():
		parts.append("Big Picture")
	if is_steam_launched():
		parts.append("Steam")
	return ", ".join(parts) if not parts.is_empty() else "generic desktop"
