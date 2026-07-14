import SwiftUI

/// 朝のタスクをコンパクトな一覧で表示。次のタスクまで見えるように1枚あたりを小さくし、
/// タップで完了・ドラッグハンドルで並び替えできるようにしてある。
struct TaskListView: View {
    @EnvironmentObject var appState: AppState
    var onFeedbackGood: (MyTask) -> Void
    var onFeedbackBad: (MyTask) -> Void

    /// 並び替え中はここだけで完結させ、appState.dailyTasks への書き戻しはドラッグ終了時にまとめて行う。
    @State private var orderedTasks: [MyTask] = []
    @State private var draggingTaskID: UUID? = nil
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragStartOrder: [MyTask] = []
    @State private var lastDragTargetIndex: Int? = nil

    /// カード1枚分の高さ＋spacing の目安。ドラッグ量から何段動かすか判定するのに使う。
    private let rowHeight: CGFloat = 88

    private var totalRemainingMinutes: Int {
        orderedTasks.reduce(0) { $0 + Int(appState.extractDurationMinutes(from: $1.duration)) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("完了まで あと\(totalRemainingMinutes)分")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.5, dampingFraction: 0.9), value: totalRemainingMinutes)

            // 行を通常のVStackレイアウトに任せると、並び替え時にドラッグ中の行自身も
            // レイアウトアニメーションへ巻き込まれる。絶対位置で配置し、掴んだ行は
            // 指へ直接追従、他の行だけを移動アニメーションさせる。
            ZStack(alignment: .top) {
                ForEach(orderedTasks) { task in
                    let index = orderedTasks.firstIndex(where: { $0.id == task.id }) ?? 0
                    let isDragging = draggingTaskID == task.id

                    TaskRow(
                        task: task,
                        isDragging: isDragging,
                        dragGesture: dragGesture(for: task),
                        onComplete: { complete(task) },
                        onFeedbackGood: { onFeedbackGood(task) },
                        onFeedbackBad: { onFeedbackBad(task) }
                    )
                    .frame(maxWidth: .infinity)
                    .offset(y: CGFloat(index) * rowHeight + (isDragging ? dragOffsetY : 0))
                    .animation(
                        isDragging ? nil : .spring(response: 0.28, dampingFraction: 0.9),
                        value: index
                    )
                    .zIndex(isDragging ? 1 : 0)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
            .frame(height: max(0, CGFloat(orderedTasks.count) * rowHeight - 12), alignment: .top)
        }
        .onAppear { syncOrder() }
        .onChange(of: appState.dailyTasks) { _, _ in
            guard draggingTaskID == nil else { return }
            syncOrder()
        }
    }

    private func syncOrder() {
        orderedTasks = appState.dailyTasks.filter { !$0.isCompleted }
    }

    private func dragGesture(for task: MyTask) -> AnyGesture<DragGesture.Value> {
        AnyGesture(
            // 行の位置が変わってもtranslationが変化しない、画面固定の座標系を使う。
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    if draggingTaskID == nil {
                        draggingTaskID = task.id
                        dragStartOrder = orderedTasks
                        lastDragTargetIndex = orderedTasks.firstIndex(where: { $0.id == task.id })
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }

                    guard let startIndex = dragStartOrder.firstIndex(where: { $0.id == task.id }) else { return }
                    let moveBy = Int((value.translation.height / rowHeight).rounded())
                    let targetIndex = min(max(startIndex + moveBy, 0), dragStartOrder.count - 1)

                    // 行自体は targetIndex の位置へ移るため、その移動量を指の移動量から引いて
                    // ドラッグ中のカードが常に指の下に留まるようにする。
                    dragOffsetY = value.translation.height - CGFloat(targetIndex - startIndex) * rowHeight

                    guard targetIndex != lastDragTargetIndex else { return }

                    var nextOrder = dragStartOrder
                    let movingTask = nextOrder.remove(at: startIndex)
                    nextOrder.insert(movingTask, at: targetIndex)

                    orderedTasks = nextOrder
                    lastDragTargetIndex = targetIndex
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                        draggingTaskID = nil
                        dragOffsetY = 0
                    }
                    dragStartOrder = []
                    lastDragTargetIndex = nil
                    commitOrder()
                }
        )
    }

    private func commitOrder() {
        var reordered = orderedTasks
        reordered.append(contentsOf: appState.dailyTasks.filter { $0.isCompleted })
        appState.dailyTasks = reordered
    }

    private func complete(_ task: MyTask) {
        guard let index = appState.dailyTasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            orderedTasks.removeAll { $0.id == task.id }
            appState.dailyTasks[index].isCompleted = true
        }
    }
}

/// タスク1行の見た目。カード全体タップで完了、右端のハンドルをドラッグで並び替え。
private struct TaskRow: View {
    let task: MyTask
    let isDragging: Bool
    let dragGesture: AnyGesture<DragGesture.Value>
    var onComplete: () -> Void
    var onFeedbackGood: () -> Void
    var onFeedbackBad: () -> Void

    @State private var hasGivenFeedback: Bool = false
    @State private var isCompleting: Bool = false
    @State private var ringTrim: CGFloat = 0
    @State private var checkmarkPop: Bool = false

    var body: some View {
        Button {
            guard !isCompleting else { return }
            isCompleting = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.3)) {
                ringTrim = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                    checkmarkPop = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                onComplete()
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: taskIcon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.Palette.accentLight)
                    .frame(width: 44, height: 44)
                    .background(Theme.Palette.accent.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(task.duration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                if task.source == "ai" && !hasGivenFeedback {
                    HStack(spacing: 14) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onFeedbackGood()
                            withAnimation(.spring()) { hasGivenFeedback = true }
                        } label: {
                            Image(systemName: "hand.thumbsup")
                        }
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onFeedbackBad()
                            withAnimation(.spring()) { hasGivenFeedback = true }
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
                }

                // 右端: 並び替え用ハンドル（左のアイコンと同サイズで左右対称に）
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .contentShape(Circle())
                    // ドラッグにならない軽いタップが親の完了Buttonへ抜けて誤完了しないよう、ここで吸収する
                    .onTapGesture {}
                    .gesture(dragGesture)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDragging ? 0.35 : 0.14), lineWidth: isDragging ? 1.5 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.green.opacity(isCompleting ? 0.35 : 0))
            )
            .overlay {
                if isCompleting {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: ringTrim)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)

                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.green)
                            .scaleEffect(checkmarkPop ? 1.0 : 0.3)
                            .opacity(checkmarkPop ? 1 : 0)
                    }
                    .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: isDragging ? 14 : 0, y: isDragging ? 6 : 0)
            .scaleEffect(isDragging ? 1.03 : (isCompleting ? 0.97 : 1.0))
            .animation(.easeOut(duration: 0.2), value: isCompleting)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
        }
        .buttonStyle(.plain)
    }

    private var taskIcon: String {
        switch task.title {
        case let t where t.contains("出発"): return "figure.walk"
        case let t where t.contains("朝食"): return "cup.and.saucer.fill"
        case let t where t.contains("服薬"), let t where t.contains("薬"): return "pills.fill"
        case let t where t.contains("シャワー"), let t where t.contains("洗面"): return "shower.fill"
        case let t where t.contains("着替"): return "tshirt.fill"
        default: return "checkmark.circle"
        }
    }
}
