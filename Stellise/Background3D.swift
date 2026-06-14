//
//  Background3D.swift
//  Stellise
//
//  リデザイン設計図 §4-1 / §3。背景を画像（bg_*, image-space-background）から
//  SceneKitの「本物の3D」へ置き換える。天気グラデの上に3D天体（月・太陽）を
//  ライティング＋カメラbloomで発光させ、夜は3D星空を散らす。アセット不要・全て生成。
//
//  天体は「時刻に応じて左→上→右へ弧を描いて移動」する（朝＝東/左、正午＝南中/上、
//  夕＝西/右）。晴れの太陽はレンズフレア的に強めに発光させ、光に満ちた印象にする。
//

import SwiftUI
import SceneKit

/// 決定論的な簡易乱数（0..1）。月テクスチャを毎回同じ配置で生成するため。
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        let v = (state &* 0x2545F4914F6CDD1D) >> 11
        return Double(v) / Double(1 << 53)
    }
}

// MARK: - 公開ビュー

/// 天気コンディションに応じた3D背景（グラデ＋3D天体＋星空）。
/// DayView / NightView の `Image(...)` 背景の置き換え先。
struct Background3DView: View {
    let condition: WeatherCondition

    var body: some View {
        ZStack {
            // ベースは §2 の天気連動グラデ
            condition.gradient
                .ignoresSafeArea()

            // 3Dレイヤー（透過SCNView）。10分ごとに現在時刻を反映し、天体を弧上で動かす。
            TimelineView(.periodic(from: .now, by: 600)) { context in
                CelestialSceneView(condition: condition, hour: Self.hour(from: context.date))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    /// 0.0〜24.0 の小数時刻（分を含む）。
    private static func hour(from date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60.0
    }

    /// 起動時に月テクスチャ/グロウ画像を先に生成しておき、初回表示の一瞬の空白を防ぐ。
    static func preheat() {
        _ = SceneBuilder.makeScene(for: .night, hour: 0)
        _ = SceneBuilder.makeScene(for: .clear, hour: 12)
    }
}

// MARK: - SceneKit 透過ビュー

/// 透過背景の SCNView を SwiftUI に埋め込み、3D天体シーンを描画する。
private struct CelestialSceneView: UIViewRepresentable {
    let condition: WeatherCondition
    let hour: Double

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear          // グラデを透かす
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true        // 自転アニメ用
        view.preferredFramesPerSecond = 30     // 背景なので省電力

        let scene = SceneBuilder.makeScene(for: condition, hour: hour)
        view.scene = scene.scene
        context.coordinator.condition = condition
        context.coordinator.body = scene.body
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // コンディション変化 → シーンごと差し替え
        if context.coordinator.condition != condition {
            context.coordinator.condition = condition
            let scene = SceneBuilder.makeScene(for: condition, hour: hour)
            view.scene = scene.scene
            context.coordinator.body = scene.body
            return
        }
        // 時刻変化（10分ごと）→ 天体だけを新しい弧上の位置へゆっくり移動
        let isNight = condition == .night || condition == .dawn
        let target = SceneBuilder.celestialPosition(hour: hour, isNight: isNight)
        let move = SCNAction.move(to: target, duration: 3.0)
        move.timingMode = .easeInEaseOut
        context.coordinator.body?.runAction(move)
    }

    func makeCoordinator() -> Coordinator { Coordinator(condition: condition) }

    final class Coordinator {
        var condition: WeatherCondition
        weak var body: SCNNode?     // 天体ノード（位置更新用）
        init(condition: WeatherCondition) { self.condition = condition }
    }
}

// MARK: - シーン生成

private enum SceneBuilder {

    /// 生成したシーンと、後から動かす天体ノードの参照。
    struct Built {
        let scene: SCNScene
        let body: SCNNode
    }

    /// 天体の見た目パラメータ（条件ごと）。
    private struct CelestialStyle {
        let color: UIColor          // 天体の基本色
        let emission: UIColor       // 自発光（bloomで光る）
        let emissionIntensity: CGFloat
        let lightColor: UIColor     // 当てる光
        let showStars: Bool         // 星空を出すか
        let bloom: CGFloat          // 発光強度
        let bloomThreshold: CGFloat // 低いほど光る範囲が広い
        let bloomBlur: CGFloat      // ブルームのにじみ半径
        let radius: CGFloat
        let constantLit: Bool       // true=陰影なしの白熱体（太陽）, false=PBR陰影（月）
        let isMoon: Bool            // true=月のクレーター表面テクスチャを貼る
        let glowPeakAlpha: CGFloat  // ハロー中心の不透明度（太陽=強, 月=弱）
        let glowScale: CGFloat      // ハロー板の大きさ（半径倍率）
    }

    static func makeScene(for condition: WeatherCondition, hour: Double) -> Built {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let style = style(for: condition)

        addCamera(to: scene, bloom: style.bloom, threshold: style.bloomThreshold, blur: style.bloomBlur)
        addAmbient(to: scene, condition: condition)
        addKeyLight(to: scene, color: style.lightColor)
        let isNight = condition == .night || condition == .dawn
        let body = addCelestialBody(to: scene, style: style,
                                    position: celestialPosition(hour: hour, isNight: isNight))
        if style.showStars { addStars(to: scene) }

        return Built(scene: scene, body: body)
    }

    /// 時刻(0..24)から天体の弧上の位置を返す。左(東/日の出)→上(南中)→右(西/日没)。
    /// 昼: 6時=日の出(左下), 12時=南中(上), 18時=日没(右下)。
    /// 夜: 18時=月の出(左下), 0時=南中(上), 6時=月没(右下)。
    static func celestialPosition(hour: Double, isNight: Bool) -> SCNVector3 {
        let progress: Double
        if isNight {
            var h = hour
            if h < 6 { h += 24 }            // 0..6時 → 24..30 に連続化
            progress = (h - 18) / 12        // 18→0, 24→0.5, 30(6時)→1
        } else {
            progress = (hour - 6) / 12       // 6→0, 12→0.5, 18→1
        }
        let p = max(0, min(1, progress))
        let angle = p * Double.pi            // 0..π の半円弧
        // やや左寄りの弧。右上は設定歯車を置くので天体を被らせない（朝日も左上が映える）。
        let x = Float(-cos(angle)) * 1.85 - 0.55 // 左端-2.4 → 南中-0.55 → 右1.3
        let y = Float(sin(angle)) * 2.6 + 1.6    // 出入り=1.6, 南中=4.2（常に画面内）
        return SCNVector3(x, y, -0.5)
    }

    private static func style(for condition: WeatherCondition) -> CelestialStyle {
        switch condition {
        case .night:
            // 月: クレーター表面＋淡い陰影。グロウは控えめ（白熱した球にしない）。
            return CelestialStyle(
                color: UIColor(red: 0.80, green: 0.79, blue: 0.86, alpha: 1),    // ほんのり寒色の月面
                emission: UIColor(red: 0.60, green: 0.58, blue: 0.78, alpha: 1), // 暗部のアースシャイン/ハロー色
                emissionIntensity: 0.05,
                lightColor: UIColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1),
                showStars: true, bloom: 0.28, bloomThreshold: 0.62, bloomBlur: 16,
                radius: 0.9, constantLit: false, isMoon: true,
                glowPeakAlpha: 0.22, glowScale: 3.2)
        case .dawn:
            return CelestialStyle(
                color: UIColor(red: 0.84, green: 0.80, blue: 0.86, alpha: 1),
                emission: UIColor(red: 0.74, green: 0.62, blue: 0.72, alpha: 1),
                emissionIntensity: 0.06,
                lightColor: UIColor(red: 1.0, green: 0.92, blue: 0.86, alpha: 1),
                showStars: true, bloom: 0.3, bloomThreshold: 0.58, bloomBlur: 16,
                radius: 0.9, constantLit: false, isMoon: true,
                glowPeakAlpha: 0.26, glowScale: 3.6)
        case .clear:
            // 晴れの太陽: iOS天気アプリ風の自然なフレア。小さい白熱コア＋大きく柔らかいブルーム。
            return CelestialStyle(
                color: UIColor(red: 1.0, green: 0.99, blue: 0.96, alpha: 1),     // 白いコア（ごく暖色）
                emission: UIColor(red: 1.0, green: 0.95, blue: 0.82, alpha: 1),  // 柔らかい暖色グロウ
                emissionIntensity: 0.0,
                lightColor: UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1),
                showStars: false, bloom: 0.55, bloomThreshold: 0.5, bloomBlur: 22,
                radius: 0.34, constantLit: true, isMoon: false,
                glowPeakAlpha: 0.95, glowScale: 17)
        case .dusk:
            // 夕暮れの沈む太陽（暖色の柔らかいフレア）。日中と同じ太陽だが赤橙に。
            return CelestialStyle(
                color: UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1),
                emission: UIColor(red: 1.0, green: 0.74, blue: 0.48, alpha: 1),   // 夕焼けのオレンジ
                emissionIntensity: 0.0,
                lightColor: UIColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1),
                showStars: false, bloom: 0.55, bloomThreshold: 0.5, bloomBlur: 22,
                radius: 0.36, constantLit: true, isMoon: false,
                glowPeakAlpha: 0.95, glowScale: 17)
        case .cloudy:
            return CelestialStyle(
                color: UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1),     // 雲ごしの淡い光
                emission: UIColor(red: 0.9, green: 0.93, blue: 0.99, alpha: 1),
                emissionIntensity: 0.0,
                lightColor: UIColor(white: 0.95, alpha: 1),
                showStars: false, bloom: 0.5, bloomThreshold: 0.5, bloomBlur: 26,
                radius: 0.6, constantLit: true, isMoon: false,
                glowPeakAlpha: 0.6, glowScale: 8)
        case .rain:
            return CelestialStyle(
                color: UIColor(red: 0.62, green: 0.68, blue: 0.85, alpha: 1),
                emission: UIColor(red: 0.5, green: 0.56, blue: 0.74, alpha: 1),
                emissionIntensity: 0.1,
                lightColor: UIColor(white: 0.8, alpha: 1),
                showStars: false, bloom: 0.25, bloomThreshold: 0.55, bloomBlur: 20,
                radius: 0.8, constantLit: true, isMoon: false,
                glowPeakAlpha: 0.4, glowScale: 6)
        case .snow:
            return CelestialStyle(
                color: UIColor(white: 0.98, alpha: 1),
                emission: UIColor(white: 0.95, alpha: 1),
                emissionIntensity: 0.0,
                lightColor: UIColor(white: 0.97, alpha: 1),
                showStars: false, bloom: 0.5, bloomThreshold: 0.5, bloomBlur: 26,
                radius: 0.6, constantLit: true, isMoon: false,
                glowPeakAlpha: 0.6, glowScale: 8)
        }
    }

    // MARK: パーツ

    private static func addCamera(to scene: SCNScene, bloom: CGFloat, threshold: CGFloat, blur: CGFloat) {
        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.bloomIntensity = bloom
        camera.bloomThreshold = threshold
        camera.bloomBlurRadius = blur
        camera.wantsExposureAdaptation = false

        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(0, 0, 9)
        scene.rootNode.addChildNode(node)
    }

    private static func addAmbient(to scene: SCNScene, condition: WeatherCondition) {
        let light = SCNLight()
        light.type = .ambient
        // 晴れは環境光を上げて全体を明るく
        light.intensity = condition == .clear ? 320 : 120
        light.color = UIColor(white: condition.isBright ? 0.8 : 0.6, alpha: 1)
        let node = SCNNode()
        node.light = light
        scene.rootNode.addChildNode(node)
    }

    private static func addKeyLight(to scene: SCNScene, color: UIColor) {
        // 左斜め前から当てて球に陰影（=三日月の陰り）を作る
        let light = SCNLight()
        light.type = .omni
        light.intensity = 1100
        light.color = color
        let node = SCNNode()
        node.light = light
        node.position = SCNVector3(-6, 4, 5)
        scene.rootNode.addChildNode(node)
    }

    @discardableResult
    private static func addCelestialBody(to scene: SCNScene, style: CelestialStyle,
                                         position: SCNVector3) -> SCNNode {
        let sphere = SCNSphere(radius: style.radius)
        sphere.segmentCount = 64

        let material = SCNMaterial()
        if style.constantLit {
            // 太陽: 陰影なしの白いコア
            material.lightingModel = .constant
            material.diffuse.contents = style.color
        } else if style.isMoon {
            // 月: クレーター表面テクスチャ＋PBR。左からの光で欠け際（ターミネーター）を出す。
            material.lightingModel = .physicallyBased
            material.diffuse.contents = tintedMoonTexture(style.color)
            material.emission.contents = style.emission   // 暗部のアースシャイン（薄く）
            material.emission.intensity = style.emissionIntensity
            material.roughness.contents = 0.95
            material.metalness.contents = 0.0
        } else {
            // 雨など: ぼんやりしたPBR球
            material.lightingModel = .physicallyBased
            material.diffuse.contents = style.color
            material.emission.contents = style.emission
            material.emission.intensity = style.emissionIntensity
            material.roughness.contents = 0.9
            material.metalness.contents = 0.0
        }
        sphere.firstMaterial = material

        let node = SCNNode(geometry: sphere)
        node.position = position

        // すべての天体に放射状グラデ板のハローを付ける（太陽=強い暖色、月=控えめな寒色）
        // 強いグロウ（=太陽）は真円だと不自然なので光条＋ストリークで崩す。
        addGlowSprite(to: node, baseRadius: style.radius, color: style.emission,
                      peakAlpha: style.glowPeakAlpha, scale: style.glowScale,
                      rays: style.glowPeakAlpha > 0.85)

        // 球体（月・雨）はゆっくり自転
        if !style.constantLit {
            let spin = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 140)
            node.runAction(.repeatForever(spin))
        }

        scene.rootNode.addChildNode(node)
        return node
    }

    /// カメラに正対する板に放射状グラデ（中心=色 → 外周=透明）を貼り、柔らかいグロウを出す。
    /// 透過SCNViewでも通常のアルファ合成なので背後のグラデと自然に重なる。
    private static func addGlowSprite(to node: SCNNode, baseRadius: CGFloat, color: UIColor,
                                     peakAlpha: CGFloat, scale: CGFloat, rays: Bool) {
        let side = baseRadius * scale
        let plane = SCNPlane(width: side, height: side)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = rays
            ? sunGlowImage(color: color, peakAlpha: peakAlpha)
            : radialGlowImage(color: color, peakAlpha: peakAlpha)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        plane.firstMaterial = m

        let sprite = SCNNode(geometry: plane)
        sprite.position = SCNVector3(0, 0, -0.05)        // コアのわずか後ろ
        sprite.constraints = [SCNBillboardConstraint()]  // 常にカメラへ正対
        node.addChildNode(sprite)
    }

    /// 太陽用グロウ。iOS天気アプリ風の「自然なフレア」。
    /// 大きく柔らかいブルーム＋かすかなハローリング＋ごく控えめな斜めストリームで、
    /// 真円ののっぺり感も派手なスパイクも避け、空に溶ける自然な光にする。
    private static func sunGlowImage(color: UIColor, peakAlpha: CGFloat, size: CGFloat = 512) -> UIImage {
        let hotCore = mix(color, with: .white, t: 0.85)
        let space = CGColorSpaceCreateDeviceRGB()
        let center = CGPoint(x: size / 2, y: size / 2)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let c = ctx.cgContext

            // 1. 大きく柔らかいブルーム（中心は白熱、外周まで自然に減衰）
            let baseColors = [
                hotCore.withAlphaComponent(peakAlpha).cgColor,
                hotCore.withAlphaComponent(peakAlpha * 0.62).cgColor,
                color.withAlphaComponent(peakAlpha * 0.30).cgColor,
                color.withAlphaComponent(peakAlpha * 0.12).cgColor,
                color.withAlphaComponent(peakAlpha * 0.04).cgColor,
                color.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: baseColors,
                                  locations: [0.0, 0.05, 0.16, 0.34, 0.62, 1.0]) {
                c.drawRadialGradient(g, startCenter: center, startRadius: 0,
                                     endCenter: center, endRadius: size * 0.5, options: [])
            }

            c.setBlendMode(.plusLighter)

            // 2. かすかなハローリング（太陽の外周にうっすら光の輪）
            let ringCols = [color.withAlphaComponent(0.0).cgColor,
                            color.withAlphaComponent(0.0).cgColor,
                            color.withAlphaComponent(peakAlpha * 0.10).cgColor,
                            color.withAlphaComponent(0.0).cgColor] as CFArray
            if let rg = CGGradient(colorsSpace: space, colors: ringCols,
                                   locations: [0.0, 0.46, 0.56, 0.70]) {
                c.drawRadialGradient(rg, startCenter: center, startRadius: 0,
                                     endCenter: center, endRadius: size * 0.5, options: [])
            }

            // 3. ごく控えめな斜めの光のにじみ（レンズフレアのにじみ）。柔らかく1本だけ。
            c.saveGState()
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: CGFloat(-Double.pi / 5))   // 斜め
            c.scaleBy(x: 0.07, y: 1)
            let streak = [color.withAlphaComponent(peakAlpha * 0.22).cgColor,
                          color.withAlphaComponent(0.0).cgColor] as CFArray
            if let sg = CGGradient(colorsSpace: space, colors: streak, locations: [0, 1]) {
                c.drawRadialGradient(sg, startCenter: .zero, startRadius: 0,
                                     endCenter: .zero, endRadius: size * 0.7, options: [])
            }
            c.restoreGState()
        }
    }

    /// 中心ほど白熱し、外周で `color` に透けていく放射状グラデ画像（大気散乱っぽい多層ハロー）。
    private static func radialGlowImage(color: UIColor, peakAlpha: CGFloat, size: CGFloat = 320) -> UIImage {
        let hotCore = mix(color, with: .white, t: 0.6)   // 中心は白寄りに熱く
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let c = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let colors = [
                hotCore.withAlphaComponent(peakAlpha).cgColor,
                color.withAlphaComponent(peakAlpha * 0.85).cgColor,
                color.withAlphaComponent(peakAlpha * 0.40).cgColor,
                color.withAlphaComponent(peakAlpha * 0.12).cgColor,
                color.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.10, 0.30, 0.60, 1.0]
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }
            c.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                 endCenter: center, endRadius: size / 2, options: [])
        }
    }

    /// 2色を t で線形補間。
    private static func mix(_ a: UIColor, with b: UIColor, t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                       blue: ab + (bb - ab) * t, alpha: 1)
    }

    // MARK: 月テクスチャ（手続き生成・キャッシュ）

    /// 月面のグレースケール基本テクスチャ（海＝暗い斑＋クレーター）。一度だけ生成。
    private static let baseMoonTexture: UIImage = makeMoonTexture()

    /// 基本テクスチャを月色で乗算した結果を返す（条件ごとの色味に対応）。
    private static func tintedMoonTexture(_ tint: UIColor) -> UIImage {
        let img = baseMoonTexture
        let renderer = UIGraphicsImageRenderer(size: img.size)
        return renderer.image { ctx in
            tint.setFill()
            ctx.fill(CGRect(origin: .zero, size: img.size))
            img.draw(in: CGRect(origin: .zero, size: img.size), blendMode: .multiply, alpha: 1)
        }
    }

    private static func makeMoonTexture(size: CGFloat = 512) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let c = ctx.cgContext
            // 明るいベース
            c.setFillColor(UIColor(white: 0.92, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // 海（マリア）= 大きく柔らかい暗い斑
            let maria: [(CGFloat, CGFloat, CGFloat)] = [
                (0.36, 0.40, 0.24), (0.60, 0.30, 0.17),
                (0.56, 0.62, 0.19), (0.30, 0.66, 0.13), (0.70, 0.55, 0.12),
            ]
            for (fx, fy, fr) in maria {
                let center = CGPoint(x: fx * size, y: fy * size)
                let rad = fr * size
                let cols = [UIColor(white: 0.62, alpha: 0.9).cgColor,
                            UIColor(white: 0.62, alpha: 0.0).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: cols, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: center, startRadius: 0,
                                         endCenter: center, endRadius: rad, options: [])
                }
            }

            // クレーター = 暗い円＋明るいリム（簡易だが立体感が出る）
            var rng = SeededRandom(seed: 20260614)
            for _ in 0..<80 {
                let cx = CGFloat(rng.next()) * size
                let cy = CGFloat(rng.next()) * size
                let cr = (0.008 + CGFloat(rng.next()) * 0.045) * size
                c.setFillColor(UIColor(white: 0.0, alpha: 0.12).cgColor)
                c.fillEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))
                c.setStrokeColor(UIColor(white: 1.0, alpha: 0.14).cgColor)
                c.setLineWidth(max(0.5, cr * 0.18))
                c.strokeEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))
            }
        }
    }

    private static func addStars(to scene: SCNScene) {
        let container = SCNNode()
        let count = 70
        for _ in 0..<count {
            let r = Float.random(in: 0.012...0.03)
            let star = SCNSphere(radius: CGFloat(r))
            star.segmentCount = 6
            let m = SCNMaterial()
            m.lightingModel = .constant
            let b = CGFloat.random(in: 0.7...1.0)
            m.diffuse.contents = UIColor(white: 1.0, alpha: 1)
            m.emission.contents = UIColor(white: b, alpha: 1)
            star.firstMaterial = m

            let node = SCNNode(geometry: star)
            // 天体より奥に、画面全体へ散らす
            node.position = SCNVector3(
                Float.random(in: -6...6),
                Float.random(in: -5...6),
                Float.random(in: -7 ... -2))
            container.addChildNode(node)

            // ゆっくり点滅
            let dim = SCNAction.fadeOpacity(to: 0.3, duration: Double.random(in: 1.2...3.0))
            let bright = SCNAction.fadeOpacity(to: 1.0, duration: Double.random(in: 1.2...3.0))
            node.runAction(.repeatForever(.sequence([dim, bright])))
        }
        scene.rootNode.addChildNode(container)
    }
}
