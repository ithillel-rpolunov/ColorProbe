import Foundation

enum AppLanguage: String, CaseIterable {
    case system, ru, en

    private static let key = "interfaceLanguage"

    static var selected: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var effective: AppLanguage {
        switch selected {
        case .ru, .en: return selected
        case .system:
            let first = Locale.preferredLanguages.first ?? "en"
            return first.hasPrefix("ru") ? .ru : .en
        }
    }
}

enum L {
    private static var ru: Bool { AppLanguage.effective == .ru }
    private static func t(_ ru: String, _ en: String) -> String { L.ru ? ru : en }

    static var menuCapture: String { t("Снять экран и выбрать цвета", "Capture Screen and Pick Colors") }
    static func menuFolder(_ path: String) -> String { t("Папка: ", "Folder: ") + path }
    static var menuChooseFolder: String { t("Выбрать папку сохранения…", "Choose Save Folder…") }
    static var menuOpenFolder: String { t("Открыть папку сохранения", "Open Save Folder") }
    static var menuRevealLast: String { t("Показать последний снимок", "Show Last Capture") }
    static var menuLanguage: String { t("Язык", "Language") }
    static var langSystem: String { t("Как в системе", "System Default") }
    static var menuQuit: String { t("Выход", "Quit") }

    static var panelPrompt: String { t("Выбрать", "Choose") }
    static var panelMessage: String { t("Папка для сохранения снимков с цветами", "Folder for saving annotated captures") }

    static var captureFailed: String { t("Не удалось сделать снимок экрана", "Could not capture the screen") }
    static var displayNotFound: String { t("Не удалось найти дисплей для захвата.", "Could not find the display to capture.") }
    static var permissionTitle: String { t("Нужен доступ к записи экрана", "Screen Recording permission required") }
    static var permissionText: String {
        t("Разрешите ColorProbe в «Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного звука», затем перезапустите приложение.",
          "Allow ColorProbe in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch the app.")
    }
    static var openSettings: String { t("Открыть настройки", "Open Settings") }
    static var later: String { t("Позже", "Later") }
    static var renderFailed: String { t("Не удалось сформировать изображение.", "Could not render the image.") }
    static func saveFailed(_ path: String, _ err: String) -> String {
        t("Не удалось сохранить файл в «\(path)»:\n\(err)", "Could not save the file to “\(path)”:\n\(err)")
    }

    static var save: String { t("Сохранить  ↩", "Save  ↩") }
    static var cancel: String { t("Отмена  ⎋", "Cancel  ⎋") }
    static func hint(_ count: Int) -> String {
        t("Точек: \(count)   Клик — точка · Тяни — сдвинуть · ПКМ — удалить · ⌘Z — отменить · Клик по строке — копировать",
          "Points: \(count)   Click — add · Drag — move · Right-click — delete · ⌘Z — undo · Click a row — copy")
    }
    static func copied(_ v: String) -> String { t("Скопировано: ", "Copied: ") + v }
    static var escAgain: String { t("Нажмите Esc ещё раз, чтобы отменить без сохранения", "Press Esc again to discard without saving") }
}
