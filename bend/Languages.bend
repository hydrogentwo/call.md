# Call.md — Transcription Languages (Bend)
# Mirrors: src/shared/constants/languages.ts
# Pure, total functions — no undefined returns, `Option` instead.

type LanguageCode:
  Auto
  En
  Es
  Fr
  De
  It
  Pt
  Nl
  Hi
  Ja
  Ko
  Zh
  Ru
  Ar
  Tr
  Pl
  Id
  Vi

object Language {
  code: LanguageCode
  api_code: String   # BCP-47 sent as `language_code` to VideoDB RTStream
  label: String      # English name
  native: String     # Endonym
}

def Languages/all() -> List(Language):
  return [
    Language { code: LanguageCode/Auto, api_code: "auto", label: "Automatic", native: "Detect from audio" },
    Language { code: LanguageCode/En, api_code: "en", label: "English",   native: "English" },
    Language { code: LanguageCode/Es, api_code: "es", label: "Spanish",   native: "Español" },
    Language { code: LanguageCode/Fr, api_code: "fr", label: "French",    native: "Français" },
    Language { code: LanguageCode/De, api_code: "de", label: "German",    native: "Deutsch" },
    Language { code: LanguageCode/It, api_code: "it", label: "Italian",   native: "Italiano" },
    Language { code: LanguageCode/Pt, api_code: "pt", label: "Portuguese",native: "Português" },
    Language { code: LanguageCode/Nl, api_code: "nl", label: "Dutch",     native: "Nederlands" },
    Language { code: LanguageCode/Hi, api_code: "hi", label: "Hindi",     native: "हिन्दी" },
    Language { code: LanguageCode/Ja, api_code: "ja", label: "Japanese",  native: "日本語" },
    Language { code: LanguageCode/Ko, api_code: "ko", label: "Korean",    native: "한국어" },
    Language { code: LanguageCode/Zh, api_code: "zh", label: "Chinese",   native: "中文" },
    Language { code: LanguageCode/Ru, api_code: "ru", label: "Russian",   native: "Русский" },
    Language { code: LanguageCode/Ar, api_code: "ar", label: "Arabic",    native: "العربية" },
    Language { code: LanguageCode/Tr, api_code: "tr", label: "Turkish",   native: "Türkçe" },
    Language { code: LanguageCode/Pl, api_code: "pl", label: "Polish",    native: "Polski" },
    Language { code: LanguageCode/Id, api_code: "id", label: "Indonesian",native: "Bahasa Indonesia" },
    Language { code: LanguageCode/Vi, api_code: "vi", label: "Vietnamese",native: "Tiếng Việt" },
  ]

def Languages/is_supported(api_code: String) -> u24:
  langs = Languages/all()
  return List/any(langs, lambda l: l.api_code == api_code)

# Returns Maybe(String) — None for "auto" / unknown / empty → engine decides
type MaybeLanguage:
  Some { value: String }
  None

def Languages/to_api_code(pref: String) -> MaybeLanguage:
  if pref == "" or pref == "auto":
    return MaybeLanguage/None
  else:
    if Languages/is_supported(pref) == 1:
      return MaybeLanguage/Some { value: pref }
    else:
      return MaybeLanguage/None

def Languages/label_for(api_code: String) -> String:
  langs = Languages/all()
  found = List/find(langs, lambda l: l.api_code == api_code)
  match found:
    case Maybe/Some:
      return found.value.label
    case Maybe/None:
      return api_code

def Languages/count() -> u24:
  return List/len(Languages/all())

# ── Validation for StartTranscription (mirrors capture.schema.ts) ───
object StartTranscriptionArgs {
  session_id: String
  mic_ws: String
  sys_ws: String
  screen_ws: String
  language_code: MaybeLanguage
}

def Languages/validate_start(args: StartTranscriptionArgs) -> u24:
  # Must have session_id and at least one WS id; language optional
  if String/len(args.session_id) == 0:
    return 0
  else:
    has_stream = String/len(args.mic_ws) > 0 or String/len(args.sys_ws) > 0 or String/len(args.screen_ws) > 0
    if has_stream == 0:
      return 0
    else:
      return 1
