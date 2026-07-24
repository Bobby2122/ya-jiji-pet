import AppKit
import Foundation
import ServiceManagement

private enum PetConfig {
    static let windowSize = NSSize(width: 276, height: 302)
    static let dayStartsAtHour = 6
    static let hatchHour = 17
    static let dinnerReminderMinute = 15
    static let dinnerReminderEndHour = 19
    static let stateKey = "DuckPetDailyStateV2"
}

private struct HatchedPet: Codable, Identifiable {
    let id: UUID
    let skinID: String
    let hatchedAt: Date
}

private struct PetState: Codable {
    var cycleDate = ""
    var eggStartedAt = Date()
    var eggSkinID = "classic"
    var hatchedToday = false
    var collection: [HatchedPet] = []
    var selectedPetID: UUID?
    var displayMode = "egg"
    var dinnerReminderEnabled = true
    var dinnerReminderShownDate: String?
}

private final class StateStore {
    static let shared = StateStore()
    private(set) var state: PetState
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        if let data = defaults.data(forKey: PetConfig.stateKey),
           let decoded = try? decoder.decode(PetState.self, from: data) {
            state = decoded
        } else {
            state = PetState()
        }
        ensureCurrentCycle(at: Date())
    }

    func mutate(_ update: (inout PetState) -> Void) {
        update(&state)
        save()
    }

    @discardableResult
    func ensureCurrentCycle(at date: Date) -> Bool {
        let expectedKey: String
        if state.cycleDate.isEmpty {
            expectedKey = Self.calendarDayKey(date)
        } else {
            expectedKey = Self.effectiveDayKey(date)
        }
        guard state.cycleDate != expectedKey else { return false }
        state.cycleDate = expectedKey
        state.eggStartedAt = date
        state.eggSkinID = SkinCatalog.randomHatchSkin().id
        state.hatchedToday = false
        state.displayMode = "egg"
        state.dinnerReminderShownDate = nil
        save()
        return true
    }

    func hatchCurrentEgg(at date: Date) -> HatchedPet? {
        guard !state.hatchedToday else { return nil }
        let pet = HatchedPet(id: UUID(), skinID: state.eggSkinID, hatchedAt: date)
        state.collection.append(pet)
        state.selectedPetID = pet.id
        state.hatchedToday = true
        state.displayMode = "pet"
        save()
        return pet
    }

    func selectedPet() -> HatchedPet? {
        if let id = state.selectedPetID,
           let selected = state.collection.first(where: { $0.id == id }) {
            return selected
        }
        return state.collection.last
    }

    func hatchDate() -> Date {
        let formatter = Self.dayFormatter
        let cycleDay = formatter.date(from: state.cycleDate) ?? Date()
        return Calendar.current.date(
            bySettingHour: PetConfig.hatchHour,
            minute: 0,
            second: 0,
            of: cycleDay
        ) ?? Date()
    }

    func eggProgress(at date: Date) -> Double {
        if state.hatchedToday { return 1 }
        let end = hatchDate()
        if end <= state.eggStartedAt { return date >= state.eggStartedAt ? 1 : 0 }
        return max(0, min(1, date.timeIntervalSince(state.eggStartedAt) / end.timeIntervalSince(state.eggStartedAt)))
    }

    func eggFrame(at date: Date) -> String {
        let progress = eggProgress(at: date)
        if progress < 0.48 { return "egg-intact-v2" }
        if progress < 0.82 { return "egg-cracked-v2" }
        return "egg-peek-v2"
    }

    func shouldHatch(at date: Date) -> Bool {
        !state.hatchedToday && date >= hatchDate()
    }

    func shouldShowDinnerReminder(at date: Date) -> Bool {
        guard state.dinnerReminderEnabled else { return false }
        let shownKey = Self.calendarDayKey(date)
        guard state.dinnerReminderShownDate != shownKey else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let afterStart = hour > PetConfig.hatchHour ||
            (hour == PetConfig.hatchHour && minute >= PetConfig.dinnerReminderMinute)
        return afterStart && hour < PetConfig.dinnerReminderEndHour
    }

    func markDinnerReminderShown(at date: Date) {
        state.dinnerReminderShownDate = Self.calendarDayKey(date)
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: PetConfig.stateKey)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func calendarDayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func effectiveDayKey(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let effectiveDate: Date
        if hour < PetConfig.dayStartsAtHour {
            effectiveDate = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            effectiveDate = date
        }
        return calendarDayKey(effectiveDate)
    }
}

private struct SkinPalette {
    let id: String
    let name: String
    let rarity: String
    let body: NSColor
    let belly: NSColor
    let beak: NSColor
    let feet: NSColor
    let cheeks: NSColor
    let prism: Bool

    var displayName: String {
        rarity == "普通" ? name : "\(name) · \(rarity)"
    }
}

private enum SkinCatalog {
    static let all: [SkinPalette] = [
        SkinPalette(id: "classic", name: "暖阳原色", rarity: "普通",
                    body: .hex(0xF5B91F), belly: .hex(0xF8DC58), beak: .hex(0xED7E61),
                    feet: .hex(0xB95338), cheeks: .hex(0xEE8B8C), prism: false),
        SkinPalette(id: "strawberry", name: "草莓奶", rarity: "少见",
                    body: .hex(0xEAB9B4), belly: .hex(0xF4E5C8), beak: .hex(0xD87982),
                    feet: .hex(0x8C514A), cheeks: .hex(0xE96573), prism: false),
        SkinPalette(id: "mint", name: "薄荷汽水", rarity: "少见",
                    body: .hex(0xA9CFC0), belly: .hex(0xD5E7D7), beak: .hex(0xE99B7C),
                    feet: .hex(0x438F8C), cheeks: .hex(0xE99572), prism: false),
        SkinPalette(id: "lavender", name: "薰衣草梦", rarity: "少见",
                    body: .hex(0xB9A9CE), belly: .hex(0xDED5E6), beak: .hex(0x976584),
                    feet: .hex(0x60425E), cheeks: .hex(0xDD7E9D), prism: false),
        SkinPalette(id: "midnight", name: "星夜", rarity: "稀有",
                    body: .hex(0x26345D), belly: .hex(0x4E5C88), beak: .hex(0xD8A548),
                    feet: .hex(0x403354), cheeks: .hex(0xD5A341), prism: false),
        SkinPalette(id: "prism", name: "虹彩", rarity: "超稀有",
                    body: .hex(0xE8B9CA), belly: .hex(0xE7E8C7), beak: .hex(0xDF7F78),
                    feet: .hex(0xA85970), cheeks: .hex(0xE7798B), prism: true)
    ]

    static func palette(_ id: String) -> SkinPalette {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    static func randomHatchSkin() -> SkinPalette {
        let roll = Double.random(in: 0..<1)
        switch roll {
        case 0..<0.68: return palette("classic")
        case 0..<0.78: return palette("strawberry")
        case 0..<0.86: return palette("mint")
        case 0..<0.94: return palette("lavender")
        case 0..<0.99: return palette("midnight")
        default: return palette("prism")
        }
    }
}

private extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    var rgb: (Double, Double, Double) {
        let color = usingColorSpace(.deviceRGB) ?? self
        return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
    }
}

private final class SpriteRenderer {
    static let shared = SpriteRenderer()
    private var sourceCache: [String: NSImage] = [:]
    private var renderedCache: [String: NSImage] = [:]

    func image(named name: String, skinID: String) -> NSImage? {
        let cacheKey = "\(name)|\(skinID)"
        if let cached = renderedCache[cacheKey] { return cached }
        guard let source = sourceImage(named: name) else { return nil }
        if skinID == "classic" || name == "egg-intact-v2" || name == "egg-cracked-v2" {
            renderedCache[cacheKey] = source
            return source
        }
        let result = recolor(source, palette: SkinCatalog.palette(skinID)) ?? source
        renderedCache[cacheKey] = result
        return result
    }

    private func sourceImage(named name: String) -> NSImage? {
        if let cached = sourceCache[name] { return cached }
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Sprites"
        ), let image = NSImage(contentsOf: url) else { return nil }
        sourceCache[name] = image
        return image
    }

    private func recolor(_ source: NSImage, palette: SkinPalette) -> NSImage? {
        guard let tiff = source.tiffRepresentation,
              let decoded = NSBitmapImageRep(data: tiff) else { return nil }
        let width = decoded.pixelsWide
        let height = decoded.pixelsHigh
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = context
            source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else { return nil }

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bitmap.bytesPerRow + x * 4
                let alpha = Double(data[offset + 3]) / 255
                if alpha < 0.02 { continue }
                let red = Double(data[offset]) / 255
                let green = Double(data[offset + 1]) / 255
                let blue = Double(data[offset + 2]) / 255
                let hsv = Self.hsv(red, green, blue)
                var target: NSColor?
                var referenceLuminance = 0.72

                if hsv.saturation > 0.25 && hsv.hue >= 32 && hsv.hue <= 68 && hsv.value > 0.42 {
                    let isBelly = green / max(red, 0.01) > 0.76 && y > height / 3
                    if palette.prism && !isBelly {
                        target = Self.prismColor(x: x, y: y, width: width, height: height)
                    } else {
                        target = isBelly ? palette.belly : palette.body
                    }
                    referenceLuminance = isBelly ? 0.84 : 0.71
                } else if hsv.saturation > 0.28 && (hsv.hue <= 31 || hsv.hue >= 345) && hsv.value > 0.38 {
                    if y > Int(Double(height) * 0.76) {
                        target = palette.feet
                        referenceLuminance = 0.48
                    } else if blue / max(red, 0.01) > 0.39 {
                        target = palette.cheeks
                        referenceLuminance = 0.68
                    } else {
                        target = palette.beak
                        referenceLuminance = 0.63
                    }
                }

                guard let target else { continue }
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let shade = max(0.38, min(1.32, luminance / referenceLuminance))
                let (tr, tg, tb) = target.rgb
                data[offset] = UInt8(max(0, min(255, tr * shade * 255)))
                data[offset + 1] = UInt8(max(0, min(255, tg * shade * 255)))
                data[offset + 2] = UInt8(max(0, min(255, tb * shade * 255)))
            }
        }

        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(bitmap)
        return result
    }

    private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0.0001 {
            if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == g { hue = 60 * (((b - r) / delta) + 2) }
            else { hue = 60 * (((r - g) / delta) + 4) }
        }
        if hue < 0 { hue += 360 }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    private static func prismColor(x: Int, y: Int, width: Int, height: Int) -> NSColor {
        let phase = (Double(x) / Double(max(width, 1)) * 0.55) +
            (Double(y) / Double(max(height, 1)) * 0.45)
        let colors: [(Double, Double, Double)] = [
            (0.91, 0.70, 0.79), (0.95, 0.86, 0.68),
            (0.70, 0.86, 0.80), (0.73, 0.72, 0.90), (0.91, 0.70, 0.79)
        ]
        let scaled = phase * Double(colors.count - 1)
        let index = min(colors.count - 2, max(0, Int(scaled)))
        let amount = scaled - Double(index)
        let a = colors[index]
        let b = colors[index + 1]
        return NSColor(calibratedRed: a.0 + (b.0 - a.0) * amount,
                       green: a.1 + (b.1 - a.1) * amount,
                       blue: a.2 + (b.2 - a.2) * amount,
                       alpha: 1)
    }
}

private final class PetWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: PetConfig.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}

private final class PetView: NSView {
    private let store = StateStore.shared
    private let imageView = NSImageView()
    private let banner = NSTextField(wrappingLabelWithString: "")
    private var bannerDismiss: DispatchWorkItem?
    private var blinkWork: DispatchWorkItem?
    private var actionWork: DispatchWorkItem?
    private var motionTimer: Timer?
    private var scheduleTimer: Timer?
    private var lastMouse = NSEvent.mouseLocation
    private var lastMouseActivity = Date()
    private var lastWalkFrameChange = Date.distantPast
    private var currentFrame = ""
    private var walkFrame = false
    private var isWalking = false
    private var isDraggingPet = false
    private var dragMoved = false
    private var dragStartMouse = NSPoint.zero
    private var dragStartWindow = NSPoint.zero
    private var hatchScheduled = false
    private var isPreviewing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupImage()
        setupBanner()
        refreshAppearance()
        scheduleBlink()
        scheduleSmallAction()
        startTimers()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if imageView.frame.insetBy(dx: 12, dy: 8).contains(point) || (!banner.isHidden && banner.frame.contains(point)) {
            return self
        }
        return nil
    }

    private func setupImage() {
        imageView.frame = NSRect(x: 14, y: 0, width: 248, height: 258)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addSubview(imageView)
    }

    private func setupBanner() {
        banner.frame = NSRect(x: 10, y: 250, width: 256, height: 46)
        banner.isHidden = true
        banner.alignment = .center
        banner.font = .systemFont(ofSize: 13, weight: .medium)
        banner.textColor = NSColor(calibratedWhite: 0.18, alpha: 1)
        banner.backgroundColor = NSColor(calibratedRed: 1, green: 0.97, blue: 0.83, alpha: 0.97)
        banner.isBordered = false
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 15
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = NSColor(calibratedWhite: 0.25, alpha: 0.15).cgColor
        addSubview(banner)
    }

    private func startTimers() {
        motionTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.updateMouseMotion()
        }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkDailySchedule()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkDailySchedule()
        }
    }

    private func activeSkinID() -> String {
        if store.state.displayMode == "egg" && !store.state.hatchedToday {
            return store.state.eggSkinID
        }
        return store.selectedPet()?.skinID ?? store.state.eggSkinID
    }

    private func setFrame(_ name: String, mirrored: Bool = false) {
        guard !isPreviewing || name.hasPrefix("egg-") else { return }
        if currentFrame != name || imageView.image == nil {
            imageView.image = SpriteRenderer.shared.image(named: name, skinID: activeSkinID())
            currentFrame = name
        }
        imageView.layer?.transform = CATransform3DMakeScale(mirrored ? -1 : 1, 1, 1)
    }

    private func refreshAppearance() {
        guard !isPreviewing else { return }
        if store.state.displayMode == "egg" && !store.state.hatchedToday {
            setFrame(store.eggFrame(at: Date()))
        } else {
            setFrame("adult-idle")
        }
    }

    private func scheduleBlink() {
        blinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isWalking, !self.isDraggingPet, !self.isPreviewing,
                  self.store.state.displayMode == "pet" || self.store.state.hatchedToday else {
                self?.scheduleBlink()
                return
            }
            self.setFrame("adult-blink")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                self?.setFrame("adult-idle")
                self?.scheduleBlink()
            }
        }
        blinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 3.2...7.5), execute: work)
    }

    private func scheduleSmallAction() {
        actionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isWalking && !self.isDraggingPet && !self.isPreviewing &&
                (self.store.state.displayMode == "pet" || self.store.state.hatchedToday) {
                self.setFrame("adult-tilt")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    self?.setFrame("adult-idle")
                }
            }
            self.scheduleSmallAction()
        }
        actionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 12...24), execute: work)
    }

    private func updateMouseMotion() {
        guard let window, !isDraggingPet, !isPreviewing else { return }
        let mouse = NSEvent.mouseLocation
        let delta = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        if delta > 1.8 {
            lastMouseActivity = Date()
            lastMouse = mouse
        }

        guard store.state.displayMode == "pet" || store.state.hatchedToday else {
            isWalking = false
            return
        }

        let recentlyMoved = Date().timeIntervalSince(lastMouseActivity) < 0.55
        let distance = mouse.x - window.frame.midX
        if recentlyMoved && abs(distance) > 58 {
            let direction: CGFloat = distance > 0 ? 1 : -1
            moveWindowHorizontally(direction: direction)
            isWalking = true
            if Date().timeIntervalSince(lastWalkFrameChange) > 0.16 {
                walkFrame.toggle()
                lastWalkFrameChange = Date()
            }
            setFrame(walkFrame ? "adult-walk-a" : "adult-walk-b", mirrored: direction > 0)
        } else {
            if isWalking {
                isWalking = false
                setFrame("adult-idle")
            } else if Date().timeIntervalSince(lastMouseActivity) > 180 && currentFrame != "adult-sleep" {
                setFrame("adult-sleep")
            }
        }
    }

    private func moveWindowHorizontally(direction: CGFloat) {
        guard let window else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin = window.frame.origin
        origin.x += direction * 4.2
        origin.x = max(visible.minX, min(visible.maxX - window.frame.width, origin.x))
        origin.y = max(visible.minY + 2, origin.y)
        window.setFrameOrigin(origin)
    }

    private func checkDailySchedule() {
        let now = Date()
        if store.ensureCurrentCycle(at: now) {
            hatchScheduled = false
            refreshAppearance()
        }
        if store.shouldHatch(at: now) && !hatchScheduled {
            hatchScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.performHatch()
            }
        }
        if store.shouldShowDinnerReminder(at: now) {
            store.markDinnerReminderShown(at: now)
            showBanner("🍚 记得吃晚饭，忙完这一小段就去吧", duration: 9)
        }
        if store.state.displayMode == "egg" && !store.state.hatchedToday {
            refreshAppearance()
        }
    }

    private func performHatch() {
        guard let pet = store.hatchCurrentEgg(at: Date()) else { return }
        isPreviewing = true
        setPreviewFrame("egg-hatched-v2", skinID: pet.skinID)
        bounce()
        let palette = SkinCatalog.palette(pet.skinID)
        showBanner("孵化成功：\(palette.displayName)！", duration: 7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { [weak self] in
            guard let self else { return }
            self.isPreviewing = false
            self.currentFrame = ""
            self.setFrame("adult-idle")
        }
    }

    private func setPreviewFrame(_ name: String, skinID: String? = nil) {
        imageView.image = SpriteRenderer.shared.image(named: name, skinID: skinID ?? activeSkinID())
        currentFrame = name
        imageView.layer?.transform = CATransform3DIdentity
    }

    private func bounce() {
        imageView.layer?.removeAnimation(forKey: "hatchBounce")
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, 16, 0, 9, 0]
        animation.duration = 0.65
        imageView.layer?.add(animation, forKey: "hatchBounce")
    }

    private func showBanner(_ text: String, duration: TimeInterval) {
        bannerDismiss?.cancel()
        banner.stringValue = text
        banner.alphaValue = 0
        banner.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            banner.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.banner.animator().alphaValue = 0
            } completionHandler: {
                self.banner.isHidden = true
            }
        }
        bannerDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartWindow = window?.frame.origin ?? .zero
        dragMoved = false
        isDraggingPet = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        if abs(dx) + abs(dy) > 4 { dragMoved = true }
        window.setFrameOrigin(NSPoint(x: dragStartWindow.x + dx, y: dragStartWindow.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingPet = false
        if !dragMoved {
            if !banner.isHidden && banner.frame.contains(convert(event.locationInWindow, from: nil)) {
                bannerDismiss?.perform()
                return
            }
            if store.state.displayMode == "pet" || store.state.hatchedToday {
                setFrame("adult-tilt")
                bounce()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in self?.setFrame("adult-idle") }
            } else {
                bounce()
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let progress = NSMenuItem(title: progressTitle(), action: nil, keyEquivalent: "")
        progress.isEnabled = false
        menu.addItem(progress)
        menu.addItem(.separator())

        let collection = menu.addItem(withTitle: "我的鸭吉吉…", action: #selector(showCollection), keyEquivalent: "")
        collection.target = self
        let dex = menu.addItem(withTitle: "异色图鉴…", action: #selector(showSkinDex), keyEquivalent: "")
        dex.target = self
        let skinPreview = menu.addItem(withTitle: "预览异色外观", action: #selector(previewSkins), keyEquivalent: "")
        skinPreview.target = self

        if !store.state.hatchedToday && store.state.displayMode != "egg" {
            let egg = menu.addItem(withTitle: "查看今天的蛋", action: #selector(showCurrentEgg), keyEquivalent: "")
            egg.target = self
        }
        let preview = menu.addItem(withTitle: "预览孵化动画", action: #selector(previewHatching), keyEquivalent: "")
        preview.target = self
        menu.addItem(.separator())

        let reminder = menu.addItem(withTitle: "晚饭提醒", action: #selector(toggleDinnerReminder), keyEquivalent: "")
        reminder.target = self
        reminder.state = store.state.dinnerReminderEnabled ? .on : .off
        let launchAtLogin = menu.addItem(withTitle: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let quit = menu.addItem(withTitle: "退出鸭吉吉", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func progressTitle() -> String {
        if store.state.hatchedToday {
            return "✓ 今天已经孵化完成"
        }
        let hatch = store.hatchDate()
        if hatch <= Date() { return "蛋正在准备破壳…" }
        let remaining = max(0, Int(hatch.timeIntervalSinceNow))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return String(format: "🥚 距离孵化 %d小时%02d分", hours, minutes)
    }

    @objc private func showCollection() {
        NSApp.activate(ignoringOtherApps: true)
        guard !store.state.collection.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "收藏库还是空的"
            alert.informativeText = "今天 17:00，第一只鸭吉吉就会孵化并住进这里。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "我的鸭吉吉"
        alert.informativeText = "每次孵化都会留下一个独立收藏。选择一只放到桌面上。"
        alert.addButton(withTitle: "换成这只")
        alert.addButton(withTitle: "取消")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 330, height: 28), pullsDown: false)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "M月d日 HH:mm"
        for pet in store.state.collection.reversed() {
            let palette = SkinCatalog.palette(pet.skinID)
            popup.addItem(withTitle: "\(palette.displayName) · \(dateFormatter.string(from: pet.hatchedAt))")
            popup.lastItem?.representedObject = pet.id.uuidString
        }
        alert.accessoryView = popup
        guard alert.runModal() == .alertFirstButtonReturn,
              let idString = popup.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        store.mutate {
            $0.selectedPetID = id
            $0.displayMode = "pet"
        }
        currentFrame = ""
        setFrame("adult-idle")
    }

    @objc private func showSkinDex() {
        NSApp.activate(ignoringOtherApps: true)
        let unlocked = Set(store.state.collection.map(\.skinID))
        let lines = SkinCatalog.all.map { skin in
            let mark = unlocked.contains(skin.id) ? "✓" : "○"
            return "\(mark) \(skin.displayName)"
        }.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = "异色图鉴  \(unlocked.count)/\(SkinCatalog.all.count)"
        alert.informativeText = lines + "\n\n概率：原色68% · 三种少见各约8–10% · 星夜5% · 虹彩1%"
        alert.addButton(withTitle: "继续孵蛋")
        alert.runModal()
    }

    @objc private func showCurrentEgg() {
        store.mutate { $0.displayMode = "egg" }
        currentFrame = ""
        refreshAppearance()
    }

    @objc private func previewHatching() {
        guard !isPreviewing else { return }
        isPreviewing = true
        let skin = activeSkinID()
        let frames = ["egg-intact-v2", "egg-cracked-v2", "egg-peek-v2", "egg-hatched-v2", "adult-idle"]
        for (index, frame) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.85) { [weak self] in
                self?.setPreviewFrame(frame, skinID: skin)
                self?.bounce()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self else { return }
            self.isPreviewing = false
            self.currentFrame = ""
            self.refreshAppearance()
        }
    }

    @objc private func previewSkins() {
        guard !isPreviewing else { return }
        isPreviewing = true
        for (index, skin) in SkinCatalog.all.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.15) { [weak self] in
                self?.setPreviewFrame("adult-idle", skinID: skin.id)
                self?.showBanner(skin.displayName, duration: 0.95)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(SkinCatalog.all.count) * 1.15 + 0.4) { [weak self] in
            guard let self else { return }
            self.isPreviewing = false
            self.currentFrame = ""
            self.refreshAppearance()
        }
    }

    @objc private func toggleDinnerReminder() {
        store.mutate { $0.dinnerReminderEnabled.toggle() }
        showBanner(store.state.dinnerReminderEnabled ? "晚饭提醒已开启" : "晚饭提醒已关闭", duration: 3)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                showBanner("开机自动启动已关闭", duration: 3)
            } else {
                try SMAppService.mainApp.register()
                showBanner("开机自动启动已开启", duration: 3)
            }
        } catch {
            showBanner("设置失败，请在系统设置的登录项中检查", duration: 5)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow: PetWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let window = PetWindow()
        window.contentView = PetView(frame: NSRect(origin: .zero, size: PetConfig.windowSize))
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.maxX - PetConfig.windowSize.width - 24,
                y: visible.minY + 4
            ))
        }
        window.orderFrontRegardless()
        petWindow = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
