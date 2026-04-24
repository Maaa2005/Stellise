//
//  TaskSetupView.swift
//  Stellise
//
//  Created by yuu on 2025/11/04.
//
import SwiftUI

// ★★★ キーボードフォーカスを管理するための「状態」 ★★★
private enum FocusedField {
    case newTask
}

// Kivyの <TaskSetupScreen>: に相当
struct TaskSetupView: View {
    
    // アプリ全体の「脳」を受け取る
    @EnvironmentObject var appState: AppState
    
    // Kivyの id: new_task_input に相当
    @State private var newTaskTitle: String = ""
    
    // ★★★ @FocusState プロパティを追加 ★★★
    // focusedField が .newTask ならキーボード表示、nil なら非表示
    @FocusState private var focusedField: FocusedField?

        
        // ★追加: アラートと画面遷移の制御フラグ
        @State private var showAIAlert = false
        @State private var navigateToCalendar = false
    
    // Kivyの ScrollView(do_scroll_x=True) に相当するタスク例
    let taskExamples = [
        "顔を洗う", "朝ご飯を食べる", "コーヒーを飲む",
        "シャワーを浴びる", "着替える", "歯を磨く"
    ]
    
    // -----------------------------------------------------------------
    // UI（見た目）の定義
    // -----------------------------------------------------------------
    var body: some View {
        VStack {
            Text("ステップ 5 / 5")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)

            VStack(spacing: 20) {
                Text("あなたの一般的な\nタスクは何ですか？")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("以下の例をタップするか、独自に追加してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                // --- Kivyのタスク例 ScrollView に相当 ---
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(taskExamples, id: \.self) { taskName in
                            Button(action: {
                                // ボタンが押されたらリストに追加
                                addTask(name: taskName)
                            }) {
                                Text(taskName)
                                    .font(.footnote)
                                    .padding(10)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain) // ボタンのデフォルトの青色を消す
                        }
                    }
                    .padding(.horizontal)
                }
                
                // --- Kivyの MDTextField + MDRaisedButton("追加") に相当 ---
                HStack {
                    TextField("新しいタスクを入力", text: $newTaskTitle)
                        .textFieldStyle(.roundedBorder)
                        // ★★★ TextField と FocusState を紐付ける ★★★
                        .focused($focusedField, equals: .newTask)
                        // (オプション: Enterキーでも追加できるようにする)
                        .onSubmit {
                            onAddTask()
                        }
                    
                    Button("追加") {
                        // ★★★ onAddTask 関数を呼び出す ★★★
                        onAddTask()
                    }
                    .disabled(newTaskTitle.isEmpty) // 空欄なら無効化
                }
                .padding(.horizontal)

                // --- Kivyの task_list_layout (MDList) に相当 ---
                // $appState.userData.masterTasks を直接表示・変更するリスト
                List {
                    // ForEachで $appState.userData.masterTasks をループ
                    ForEach($appState.userData.masterTasks, id: \.self) { $taskName in
                        // $taskName を渡すことで、リスト上で直接編集も可能になる
                        Text(taskName)
                    }
                    .onDelete(perform: deleteTask) // スワイプで削除する機能
                }
                .listStyle(.inset) // リストのスタイル
                
                // "次へ" ボタン (CalendarLinkScreenへ)
                // ★★★ 修正: "次へ" ボタン (AI同意アラート付き) ★★★
                                Button(action: {
                                    focusedField = nil // キーボードを閉じる
                                    appState.save()
                                    print("タスクリストを保存しました。")
                                    // 同意アラートを表示する
                                    showAIAlert = true
                                }) {
                                    Text("次へ")
                                        .fontWeight(.semibold)
                                        .frame(width: 300, height: 50)
                                        .background(Color.blue)
                                        .foregroundStyle(Color.white)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 10)
                                .alert("AI機能のデータ利用について", isPresented: $showAIAlert) {
                                    Button("キャンセル", role: .cancel) { }
                                    Button("同意する") {
                                        // 同意したら次の画面へ進むフラグをオン
                                        navigateToCalendar = true
                                    }
                                } message: {
                                    Text("StelliseのAI機能（タスク提案など）を利用するため、あなたのタスク名やカレンダーの予定を、安全な通信で第三者のAIサービス（Google Gemini）へ送信します。データは回答生成のみに使用されます。")
                                }
                                // アラートで同意した時だけ CalendarLinkView へ遷移
                                .navigationDestination(isPresented: $navigateToCalendar) {
                                    CalendarLinkView()
                                }
            }
            .padding(.bottom)
        }
        .navigationTitle("タスク設定")
    }
    
    // -----------------------------------------------------------------
    // 3. ロジック（Kivyの .py ファイル側メソッド）
    // -----------------------------------------------------------------
    
    // ★★★ 「追加」ボタンと「Enter」キーの処理を共通化 ★★★
    private func onAddTask() {
        // --- ここが重要 ---
        // (1) まずキーボードを閉じる
        focusedField = nil
        
        // (2) その後にリストの更新処理を行う
        let trimmedName = newTaskTitle.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty && !appState.userData.masterTasks.contains(trimmedName) {
            appState.userData.masterTasks.append(trimmedName)
        }
        
        // (3) TextFieldをクリア
        newTaskTitle = ""
    }
    
    // タスク例のボタンから呼ばれる
    private func addTask(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty && !appState.userData.masterTasks.contains(trimmedName) {
            appState.userData.masterTasks.append(trimmedName)
        }
    }
    
    // Kivyの delete_task に相当
    private func deleteTask(at offsets: IndexSet) {
        appState.userData.masterTasks.remove(atOffsets: offsets)
    }
}

// プレビュー用
struct TaskSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TaskSetupView()
                .environmentObject(AppState())
        }
    }
}
