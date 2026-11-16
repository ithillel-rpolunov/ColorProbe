import Foundation

enum Settings {
    private static let folderKey = "saveFolderPath"

    static var saveFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: folderKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { UserDefaults.standard.set(newValue.path, forKey: folderKey) }
    }
}
