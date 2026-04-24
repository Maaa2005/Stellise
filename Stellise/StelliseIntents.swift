import Foundation
import AppIntents

// ★ 修正1: saveURLプロパティを削除し、関数内で生成するように変更
// これで変数の競合エラーが消えます
struct SharedDataLoader: Sendable {
    private static let appGroupID = "group.com.stellise"
    
    // URLを生成するだけのヘルパー関数 (プロパティではない)
    private static func getSaveURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("my_routines.json")
    }
    
    // nonisolated をつけて、どこからでも呼べるようにする
    nonisolated static func loadUserData() -> UserData? {
        // 関数内でURLを取得
        guard let url = getSaveURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserData.self, from: data)
    }
    
    // nonisolated をつけて、どこからでも呼べるようにする
    nonisolated static func save(_ data: UserData) {
        guard let url = getSaveURL() else { return }
        try? JSONEncoder().encode(data).write(to: url)
    }
}

// ★ 修正2: 「今日のタスクを読み上げ」
struct ReadTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "今日のタスクを読み上げ"
    static var description = IntentDescription("Stelliseの今日のタスクを確認します。")

    func perform() async throws -> some IntentResult {
        // static メソッドを直接呼ぶ
        if let data = SharedDataLoader.loadUserData() {
            if let nextTask = data.dailyTasks.first(where: { !$0.isCompleted }) {
                let timeText = formatTime(nextTask.time)
                let dialogString = "次のタスクは、\(timeText)、\(nextTask.title)、です。"
                return .result(dialog: IntentDialog(stringLiteral: dialogString))
            } else {
                return .result(dialog: "すべてのタスクが完了しています。お疲れ様でした！")
            }
        } else {
            return .result(dialog: "データの読み込みに失敗しました。アプリを起動してください。")
        }
    }
    
    private func formatTime(_ time: String) -> String {
        let components = time.split(separator: ":").map { Int($0) ?? 0 }
        if components.count >= 2 {
            let hour = components[0]
            let minute = components[1]
            return minute == 0 ? "\(hour)時" : "\(hour)時\(minute)分"
        }
        return time
    }
}

// ★ 修正3: 「現在のタスクを完了」
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "現在のタスクを完了"
    static var description = IntentDescription("現在のタスクを完了済みにします。")

    func perform() async throws -> some IntentResult {
        guard var data = SharedDataLoader.loadUserData() else {
            return .result(dialog: "データが見つかりません。")
        }
        
        if let index = data.dailyTasks.firstIndex(where: { !$0.isCompleted }) {
            let taskTitle = data.dailyTasks[index].title
            data.dailyTasks[index].isCompleted = true
            
            SharedDataLoader.save(data)
            
            return .result(dialog: IntentDialog(stringLiteral: "\(taskTitle)を完了しました。次はどうしますか？"))
        }
        
        return .result(dialog: "完了するタスクはありません。")
    }
}

// ★ 修正4: ショートカット登録
struct StelliseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadTasksIntent(),
            phrases: [
                "\(.applicationName) でタスク読み上げ",
                "\(.applicationName) のタスクを教えて"
            ],
            shortTitle: "タスク読み上げ",
            systemImageName: "speaker"
        )
        
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "\(.applicationName) でタスク完了",
                "\(.applicationName) で次へ",
                "\(.applicationName) で実行済みにして"
            ],
            shortTitle: "タスク完了",
            systemImageName: "checkmark.circle"
        )
    }
}
