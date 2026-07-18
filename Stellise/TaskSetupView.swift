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

    // アラートと画面遷移の制御フラグ
    @State private var showAIAlert = false
    @State private var navigateToCalendar = false
    
    // 初期設定で選びやすい代表的な朝のタスク
    // （マイボイスコム「朝の時間の過ごし方」等の調査で実施率が高い順）
    let taskExamples = [
        "歯を磨く", "顔を洗う",
        "水・白湯を飲む", "朝ご飯を食べる",
        "着替える", "髪を整える",
        "スキンケア", "メイクをする",
        "髭を剃る", "コーヒーを飲む",
        "シャワーを浴びる", "ゴミ出し",
        "お弁当を作る", "天気・ニュースを見る"
    ]
    
    // -----------------------------------------------------------------
    // UI（見た目）の定義
    // -----------------------------------------------------------------
    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressHeader(step: 4, total: 5)

                ScrollView {
                    VStack(spacing: 18) {
                        OnboardingHero(
                            symbol: "checklist",
                            title: "朝のルーティン",
                            description: "毎朝することを選んでください。\n選んだ順番でルーティンを作成します。"
                        )
                        .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("候補から選ぶ")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("タップで追加・解除")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.textOnDarkMuted)
                            }

                            LazyVGrid(columns: taskGridColumns, spacing: 10) {
                                ForEach(taskExamples, id: \.self) { taskName in
                                    taskChoiceButton(taskName)
                                }
                            }
                        }
                        .onboardingCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("ほかのタスクを追加")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.Palette.accentLight)
                                TextField("例：薬を飲む", text: $newTaskTitle)
                                    .focused($focusedField, equals: .newTask)
                                    .submitLabel(.done)
                                    .onSubmit(onAddTask)

                                Button("追加", action: onAddTask)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(isNewTaskValid ? Theme.Palette.accentLight : .white.opacity(0.3))
                                    .disabled(!isNewTaskValid)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10)))
                        }
                        .onboardingCard()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("選んだタスク")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(appState.userData.masterTasks.count)件")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.Palette.accentLight)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Theme.Palette.accent.opacity(0.18), in: Capsule())
                            }

                            if appState.userData.masterTasks.isEmpty {
                                Label("上の候補からタスクを選んでください", systemImage: "hand.tap")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Palette.textOnDarkMuted)
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(appState.userData.masterTasks.enumerated()), id: \.element) { index, taskName in
                                        selectedTaskRow(taskName, at: index)
                                    }
                                }
                            }
                        }
                        .onboardingCard()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                }

                VStack(spacing: 0) {
                    Divider().overlay(Color.white.opacity(0.08))
                    Button {
                        focusedField = nil
                        appState.save()
                        debugLog("タスクリストを保存しました。")
                        showAIAlert = true
                    } label: {
                        OnboardingPrimaryLabel(title: "次へ")
                    }
                    .buttonStyle(PressSpringButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .alert("AI機能のデータ利用について", isPresented: $showAIAlert) {
                        Button("キャンセル", role: .cancel) { }
                        Button("同意する") { navigateToCalendar = true }
                    } message: {
                        Text("StelliseのAI機能（タスク提案など）を利用するため、あなたのタスク名やカレンダーの予定を、安全な通信で第三者のAIサービス（Google Gemini）へ送信します。データは回答生成のみに使用されます。")
                    }
                    .navigationDestination(isPresented: $navigateToCalendar) {
                        CalendarLinkView()
                    }
                }
                .background(Color(hex: "#0C0C18").opacity(0.96))
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
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

    private var isNewTaskValid: Bool {
        !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let taskGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    @ViewBuilder
    private func taskChoiceButton(_ taskName: String) -> some View {
        let isSelected = appState.userData.masterTasks.contains(taskName)
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                toggleTask(name: taskName)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.Palette.accentLight : .white.opacity(0.38))
                Text(taskName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                isSelected ? Theme.Palette.accent.opacity(0.22) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.Palette.accentLight.opacity(0.65) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(taskName)、\(isSelected ? "選択済み" : "未選択")")
    }

    private func selectedTaskRow(_ taskName: String, at index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.Palette.accentLight)
                .frame(width: 26, height: 26)
                .background(Theme.Palette.accent.opacity(0.18), in: Circle())

            Text(taskName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { moveTask(at: index, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .opacity(index == 0 ? 0.25 : 0.75)

            Button { moveTask(at: index, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == appState.userData.masterTasks.count - 1)
            .opacity(index == appState.userData.masterTasks.count - 1 ? 0.25 : 0.75)

            Button(role: .destructive) { removeTask(name: taskName) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.red.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // タスク例のボタンから呼ばれる
    private func addTask(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty && !appState.userData.masterTasks.contains(trimmedName) {
            appState.userData.masterTasks.append(trimmedName)
        }
    }

    private func toggleTask(name: String) {
        if appState.userData.masterTasks.contains(name) {
            removeTask(name: name)
        } else {
            addTask(name: name)
        }
    }

    private func removeTask(name: String) {
        appState.userData.masterTasks.removeAll { $0 == name }
    }

    private func moveTask(at index: Int, by offset: Int) {
        let destination = index + offset
        guard appState.userData.masterTasks.indices.contains(index),
              appState.userData.masterTasks.indices.contains(destination) else { return }
        appState.userData.masterTasks.swapAt(index, destination)
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
