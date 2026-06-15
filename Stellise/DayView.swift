import SwiftUI
import EventKit

struct DayView: View {

    @EnvironmentObject var appState: AppState
    @State private var isShowingReportModal: Bool = false
    @State private var isShowingAlarmPicker: Bool = false
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    private var allTasksCompleted: Bool {
        !appState.dailyTasks.isEmpty && appState.dailyTasks.allSatisfy { $0.isCompleted }
    }
    private var dateString: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "Mædæ¥ EEEE"
            return formatter.string(from: Date())
        }
    
    var body: some View {
            ZStack {
                // èæ¯ã¯ StelliseApp ã®å±æ Background3DViewï¼æâå¤ã§é£ç¶ï¼ãããã§ã¯æããªãã

                // --- ã³ã³ãã³ã ---
                if appState.isLoading {
                    // ã­ã¼ãã£ã³ã°ç»é¢
                    ZStack {
                        Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                        VStack(spacing: 24) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)
                            Text("ã¹ã±ã¸ã¥ã¼ã«ãä½æä¸­...")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .cornerRadius(24)
                    }
                    .zIndex(10)
                    
                } else if appState.connectionError {
                    // éä¿¡ã¨ã©ã¼ç»é¢
                    VStack(spacing: 20) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("éä¿¡ã¨ã©ã¼ãçºçãã¾ãã")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Button(action: {
                            Task {
                                await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium)
                            }
                        }) {
                            Text("åè©¦è¡")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.6))
                    .zIndex(9)
                    
                } else {
                    // éå¸¸ç»é¢
                    VStack(spacing: 0) {
                        // ç·æ¥ããã¼
                        if appState.isEmergencyScheduleShift {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.callout)
                                Text(appState.emergencyMessage)
                                    .font(.callout)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.85))
                        }
                        
                        // ãããã¼
                        // ãããã¼
                                            HeaderView(
                                                departureTime: appState.dailyTasks.first(where: { $0.title == "åºçº" })?.time ?? "--:--",
                                                travelTime: appState.estimatedTravelTime,
                                                feelsLikeTemp: appState.currentTempFeelsLike,
                                                iconName: appState.weatherIconName,
                                                isWeatherIconSystem: appState.isWeatherIconSystem, // âââ è¿½å  âââ
                                                travelMode: appState.userData.travelMode,
                                                routeSummary: appState.routeSummary,
                                                isDelay: appState.isTrafficDelayDetected,
                                                isBright: appState.isBrightBackground // èæ¯ã®ææã§ã¬ã©ã¹/æå­è²ãåæ¿
                                            )
                        
                        // --- æè¨ (ã¹ãã¼ãã»ãããã«ã¹ã¿ã¤ã«) ---
                        VStack(spacing: 0) {
                            // æé
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                Text(context.date, style: .time)
                                    // P0: ãã¶ã¤ã³ãã¼ã¯ã³ã®å¤§æè¨ãã©ã³ãï¼rounded + monospacedDigitï¼
                                    .font(Theme.Typography.clock(96))
                                    // èæ¯ãæããæã¯æ¿ç´ºãæãæã¯ç½
                                    .foregroundStyle(appState.isBrightBackground ? Theme.Palette.textOnBright : Theme.Palette.textOnDark)
                                    // é²ãç©ºã®æ¿æ·¡ã§æ°å­ãåãããªããããèæ¯ã®éæ¹åã«ã½ãããªå½±/ãã­ã¼ãæ·ã
                                    .shadow(color: appState.isBrightBackground ? .white.opacity(0.55) : .black.opacity(0.4),
                                            radius: appState.isBrightBackground ? 12 : 7, y: 1)
                            }

                            // æ¥ä»
                            Text(dateString)
                                .font(.system(.title3, design: .rounded, weight: .regular))
                                .tracking(3)
                                // èæ¯ãæããæã¯æ¿ç´ºãæãæã¯ç½
                                .foregroundStyle(appState.isBrightBackground ? Theme.Palette.textOnBright.opacity(0.8) : Theme.Palette.textOnDarkMuted)
                                .shadow(color: appState.isBrightBackground ? .white.opacity(0.5) : .black.opacity(0.35),
                                        radius: appState.isBrightBackground ? 8 : 5, y: 1)

                            // ã¢ã©ã¼ã ãããï¼æã§ãææ¥ã®ã¢ã©ã¼ã ãå¤æ´ã§ããå°ç·ï¼
                            Button {
                                let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                                isShowingAlarmPicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bell.fill").font(.subheadline)
                                    Text(String(format: "%02d:%02d", appState.userData.alarmHour, appState.userData.alarmMinute))
                                        .font(.system(.title3, design: .rounded, weight: .regular))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(appState.isBrightBackground ? Theme.Palette.textOnBright : Theme.Palette.textOnDark)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.6)
                                )
                                .overlay(Capsule().strokeBorder(.primary.opacity(0.28), lineWidth: 1))
                                // ééã¬ã©ã¹ãæããç©ºã§ã¯æ¿è²æå­ãæãç©ºã§ã¯ç½æå­ï¼ã¬ã©ã¹ã¯ééã®ã¾ã¾ï¼
                                .environment(\.colorScheme, appState.isBrightBackground ? .light : .dark)
                            }
                            .padding(.top, 16)
                        }
                        .padding(.vertical, 32)
                        
                        // ã¿ã¹ã¯ãªã¹ã
                        if appState.dailyTasks.isEmpty {
                            Spacer()
                            // ã¿ã¹ã¯æªçæ: èªåçæãããæåã§çæããã
                            VStack(spacing: 18) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 44, weight: .ultraLight))
                                    .foregroundStyle(.white)
                                Text("ä»æ¥ã®ã¿ã¹ã¯ã¯ã¾ã ããã¾ãã")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("å¤©æ°ã¨äºå®ãããåºçºã«éã«åã\næã®ã«ã¼ãã£ã³ãçµã¿ç«ã¦ã¾ãã")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineSpacing(4)
                                Button {
                                    let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                                    Task { await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium) }
                                } label: {
                                    Text("ã¿ã¹ã¯ãçæ")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 14)
                                        .background(Color.appAccent, in: Capsule())
                                }
                                .padding(.top, 4)
                            }
                            .padding(40)
                            .glassCard()
                            .padding(.horizontal, 32)
                            Spacer()

                        } else if allTasksCompleted {
                            Spacer()
                            // å®äºç»é¢
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 60, weight: .ultraLight))
                                    .foregroundStyle(.white)
                                
                                Text("æºåå®äº")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                
                                Text("ãã¹ã¦ã®ã¿ã¹ã¯ãå®äºãã¾ããã\nä»æ¥ãè¯ãä¸æ¥ãã")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineSpacing(4)
                            }
                            .padding(40)
                            .background(.ultraThinMaterial)
                            .cornerRadius(32)
                            Spacer()
                            
                        } else {
                            List {
                                ForEach($appState.dailyTasks) { $task in
                                    if !task.isCompleted {
                                        // ç»å ´ã¢ãã¡ã®ã¹ã¿ãã¬ã¼ç¨ã«ä¸è¦§ä¸­ã®ä½ç½®ãæ¸¡ã
                                        let rowIndex = appState.dailyTasks.firstIndex(where: { $0.id == task.id }) ?? 0
                                        // âââ ä¿®æ­£: TaskRowViewã®å¼ã³åºãã« source ãè¿½å  (UIå¤å®ç¨) âââ
                                        TaskRowView(task: $task,  onFeedbackGood: { // â appStateãè¿½å 
                                            appState.recordFeedback(taskTitle: task.title, isGood: true)
                                        },
                                                    onFeedbackBad: {
                                            appState.recordFeedback(taskTitle: task.title, isGood: false)
                                        }, index: rowIndex)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                            .padding(.vertical, 6)
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button {
                                                    // å®äºæã®è§¦è¦ãã£ã¼ãããã¯
                                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                                    generator.impactOccurred()
                                                    
                                                    withAnimation {
                                                        task.isCompleted = true
                                                    }
                                                } label: {
                                                    Label("å®äº", systemImage: "checkmark")
                                                }
                                                .tint(Color.appAccent.opacity(0.7)) // å®äºã¹ã¯ã¤ãã¯ã¢ã¯ã»ã³ãã®ãã¼ãã«ã§çµ±ä¸
                                            }
                                    }
                                }
                                
                                .onDelete { indexSet in
                                    appState.dailyTasks.remove(atOffsets: indexSet)
                                }
                                Section {
                                                                    Text("AIã¯ééãããã¨ãããã¾ããéè¦ãªæå ±ã¯ç¢ºèªãã¦ãã ããã")
                                                                        .font(.caption2)
                                                                        .foregroundStyle(.secondary)
                                                                        .frame(maxWidth: .infinity, alignment: .center)
                                                                        .listRowBackground(Color.clear)
                                                                        .listRowSeparator(.hidden)
                                                                        .padding(.top, 10)
                                                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            
            .onAppear {
            // ã¿ã¹ã¯ã¯èªåçæããªãï¼ã¢ã©ã¼ã çºç« or æåãçæããã¿ã³ã§ä½ãï¼
            if appState.lastSleepScore > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isShowingReportModal = true }
                appState.startMorningTrafficMonitoring(isPremium: subscriptionManager.isPremium)
            }
        }
        .onDisappear {
            appState.stopMorningTrafficMonitoring()
        }
        .onChange(of: appState.dailyTasks) { _, _ in
            appState.cancelSnoozeGuardIfNeeded()
        }
        .sheet(isPresented: $isShowingReportModal) {
            SleepReportModalView().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingAlarmPicker) {
            VStack(spacing: 20) {
                Text("ã¢ã©ã¼ã è¨­å®").font(.headline).padding(.top)
                DatePicker("", selection: Binding(
                    get: {
                        let comp = DateComponents(hour: appState.userData.alarmHour, minute: appState.userData.alarmMinute)
                        return Calendar.current.date(from: comp) ?? Date()
                    },
                    set: { newDate in
                        let comp = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        appState.userData.alarmHour = comp.hour ?? appState.userData.alarmHour
                        appState.userData.alarmMinute = comp.minute ?? appState.userData.alarmMinute
                    }
                ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden()
                Button("å®äº") {
                    isShowingAlarmPicker = false
                    appState.save()
                    appState.requestNotificationPermission()
                    appState.scheduleMorningAlarm()
                }.padding()
            }
            .presentationDetents([.medium])
        }
    }
}

// ==========================================
// MARK: - ãããã¼é¨å (HeaderView) ãããã«ãã¶ã¤ã³ç
// ==========================================

struct HeaderView: View {
    let departureTime: String
    let travelTime: String
    let feelsLikeTemp: String
    let iconName: String
    let isWeatherIconSystem: Bool
    
    let travelMode: String
    let routeSummary: String

    let isDelay: Bool
    /// èæ¯ãæããï¼æã»æ¥ä¸­ã®æ´å¤©ãªã©ï¼ããglassã¨æå­è²ãiOSå¤©æ°ã¢ããªé¢¨ã«åºãåããã
    let isBright: Bool

    // ç§»åææ®µã«å¿ããã¢ã¤ã³ã³
    var modeIcon: String {
        switch travelMode {
        case "driving": return "car"
        case "transit": return "tram.fill"
        case "walking": return "figure.walk"
        default:        return "car"
        }
    }
    
    var modeLabel: String {
        switch travelMode {
        case "driving": return "è»"
        case "transit": return "é»è»"
        case "walking": return "å¾æ­©"
        default:        return "ç§»å"
        }
    }
    
    /// éå»¶æã®ã¢ã¯ã»ã³ããèµ¤æ ã§ãªãããªã¬ã³ã¸ã®ã¬ã©ã¹ãã§ä¸åã«è­¦åããã
    private var delayAccent: Color { Color(red: 1.0, green: 0.55, blue: 0.15) }

    // â ã«ã©ãã«ãªè²åããå»æ­¢ããçµ±ä¸æã®ããã¢ããã¼ã³ã¸ (éå»¶æã®ã¿ãªã¬ã³ã¸)
    var statusColor: Color {
        if isDelay { return delayAccent }
        return .primary
    }
    
    var body: some View {
        HStack {
            // --- å·¦å´: åºçºã»ç§»åæå ± ---
            HStack(spacing: 12) {
                // ã¢ã¤ã³ã³
                Image(systemName: modeIcon)
                    .font(.title3)
                    .foregroundStyle(isDelay ? delayAccent : .primary.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(isDelay ? delayAccent.opacity(0.18) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    // åºçºæå»
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("åºçº")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(departureTime)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(isDelay ? delayAccent : .primary)
                    }

                    // ææ®µã»ç¶æ³ã»æè¦æé
                    Text("\(modeLabel) (\(routeSummary)) â¢ \(travelTime)")
                        .font(.caption2)
                        .foregroundStyle(isDelay ? delayAccent.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // ééã¬ã©ã¹ï¼ç©ºãéããï¼ãMaterialã¸ã® .opacity ã¯å¹ããªãã®ã§
            // ã·ã§ã¤ãã«ãã¥ã¼ä¿®é£¾å­ã® .opacity ãæãã¦ç¢ºå®ã«åéæåããã
            // éå»¶æã¯èµ¤æ ã§ãªããã¬ã©ã¹ã«ãªã¬ã³ã¸ã®è²å³ãæº¶ãããããªã¬ã³ã¸ã¬ã©ã¹ãã«ããã
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(delayAccent.opacity(isDelay ? 0.22 : 0))
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // ç¸: éå¸¸ã¯æ·¡ãç½ãéå»¶æã¯æããããªã¬ã³ã¸ã®ç¸
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isDelay ? delayAccent.opacity(0.55) : .primary.opacity(0.28),
                                  lineWidth: isDelay ? 1.0 : 0.6)
            )
            // æããç©ºã§ã¯æ¿è²æå­ãæãç©ºã§ã¯ç½æå­ã«åæ¿ï¼ã¬ã©ã¹ã¯ééã®ã¾ã¾ï¼
            .environment(\.colorScheme, isBright ? .light : .dark)

            Spacer()
            
            // --- å³å´: å¤©æ°æå ± ---
            // --- å³å´: å¤©æ°æå ± ---
                        HStack(spacing: 8) {
                            // âââ ä¿®æ­£: ãã©ã°ã«ãã£ã¦ Image ã¨ Image(systemName:) ãåºãåãã âââ
                            if isWeatherIconSystem {
                                Image(systemName: iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.primary)
                            } else {
                                Image(iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .opacity(0.9)
                            }

                            Text(feelsLikeTemp)
                                .font(.headline)
                        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // ééã¬ã©ã¹ï¼ç©ºãéããï¼ãã·ã§ã¤ãã« .opacity ãæãã¦ç¢ºå®ã«åéæåã
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.primary.opacity(0.28), lineWidth: 0.6)
            )
            // æããç©ºã§ã¯æ¿è²æå­ãæãç©ºã§ã¯ç½æå­ã«åæ¿ï¼ã¬ã©ã¹ã¯ééã®ã¾ã¾ï¼
            .environment(\.colorScheme, isBright ? .light : .dark)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}
