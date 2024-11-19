import SwiftUI
import Combine

// MARK: - Waveform Configuration
struct WaveformConfiguration {
    let primaryColor: Color
    let secondaryColor: Color
    let backgroundColor: Color
    let maxBars: Int
    let spacing: CGFloat
    let minBarHeight: CGFloat
    let maxBarHeight: CGFloat
    let barWidth: CGFloat
    let animationDuration: Double
    
    static let `default` = WaveformConfiguration(
        primaryColor: Theme.Colors.primary,
        secondaryColor: Theme.Colors.primary.opacity(0.3),
        backgroundColor: Theme.Colors.background,
        maxBars: 60,
        spacing: 2,
        minBarHeight: 4,
        maxBarHeight: 100,
        barWidth: 3,
        animationDuration: 0.15
    )
}

// MARK: - Waveform View Model
@MainActor
final class WaveformViewModel: ObservableObject {
    @Published private(set) var waveforms: [CGFloat] = []
    @Published private(set) var mirrorWaveforms: [CGFloat] = []
    @Published private(set) var circleScale: CGFloat = 1.0
    
    private let configuration: WaveformConfiguration
    private var lastUpdateTime: TimeInterval = 0
    private let minimumUpdateInterval: TimeInterval = 1.0 / 60.0 // 60 FPS max
    
    init(configuration: WaveformConfiguration = .default) {
        self.configuration = configuration
        initializeWaveforms()
        
        #if DEBUG
        print("""
        🎵 WaveformViewModel: Initialized with configuration:
        - Max Bars: \(configuration.maxBars)
        - Bar Width: \(configuration.barWidth)
        - Spacing: \(configuration.spacing)
        - Animation Duration: \(configuration.animationDuration)
        """)
        #endif
    }
    
    func initializeWaveforms() {
        guard configuration.maxBars > 0 else {
            assertionFailure("WaveformViewModel: Invalid maxBars configuration")
            return
        }
        
        waveforms = Array(repeating: 0, count: configuration.maxBars)
        mirrorWaveforms = Array(repeating: 0, count: configuration.maxBars)
        
        #if DEBUG
        print("🎵 WaveformViewModel: Waveforms initialized with \(configuration.maxBars) bars")
        #endif
    }
    
    func updateWaveform(with level: CGFloat) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastUpdateTime >= minimumUpdateInterval else {
            #if DEBUG
            print("🎵 WaveformViewModel: Skipping update due to rate limiting")
            #endif
            return
        }
        lastUpdateTime = currentTime
        
        #if DEBUG
        print("""
        🎵 WaveformViewModel: Updating waveform
        - Input Level: \(level)
        - Current Scale: \(circleScale)
        - Waveforms Count: \(waveforms.count)
        """)
        #endif
        
        // Validate input level
        let clampedLevel = max(0, min(1, level))
        if clampedLevel != level {
            #if DEBUG
            print("🎵 WaveformViewModel: Input level clamped from \(level) to \(clampedLevel)")
            #endif
        }
        
        let variation = Double.random(in: 0.8...1.2)
        let adjustedLevel = min(1.0, clampedLevel * CGFloat(variation))
        
        guard waveforms.count == configuration.maxBars else {
            #if DEBUG
            print("🎵 WaveformViewModel: Error - Waveform array size mismatch")
            #endif
            initializeWaveforms()
            return
        }
        
        waveforms.removeFirst()
        waveforms.append(adjustedLevel)
        
        // Update mirror waveforms with slight delay and variation
        Task {
            do {
                try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                await MainActor.run {
                    mirrorWaveforms.removeFirst()
                    mirrorWaveforms.append(adjustedLevel * 0.8)
                }
            } catch {
                #if DEBUG
                print("🎵 WaveformViewModel: Error updating mirror waveforms - \(error)")
                #endif
            }
        }
        
        // Update circle scale with bounds checking
        let newScale = 1.0 + (adjustedLevel * 0.5)
        if newScale.isFinite {
            circleScale = newScale
        } else {
            #if DEBUG
            print("🎵 WaveformViewModel: Warning - Invalid circle scale calculated: \(newScale)")
            #endif
            circleScale = 1.0
        }
    }
    
    // MARK: - Debug Helpers
    #if DEBUG
    func validateState() -> Bool {
        let isValid = waveforms.count == configuration.maxBars &&
                     mirrorWaveforms.count == configuration.maxBars &&
                     circleScale.isFinite &&
                     waveforms.allSatisfy { $0 >= 0 && $0 <= 1 } &&
                     mirrorWaveforms.allSatisfy { $0 >= 0 && $0 <= 1 }
        
        if !isValid {
            print("""
            🎵 WaveformViewModel: Invalid state detected
            - Waveforms count: \(waveforms.count) (expected: \(configuration.maxBars))
            - Mirror waveforms count: \(mirrorWaveforms.count) (expected: \(configuration.maxBars))
            - Circle scale: \(circleScale)
            - Invalid waveform values: \(waveforms.filter { !($0 >= 0 && $0 <= 1) })
            - Invalid mirror values: \(mirrorWaveforms.filter { !($0 >= 0 && $0 <= 1) })
            """)
        }
        
        return isValid
    }
    #endif
}

// MARK: - Enhanced Waveform View
struct EnhancedWaveformView: View {
    @StateObject private var viewModel: WaveformViewModel
    let audioLevel: CGFloat
    let configuration: WaveformConfiguration
    
    init(audioLevel: CGFloat, configuration: WaveformConfiguration = .default) {
        self.audioLevel = audioLevel
        self.configuration = configuration
        self._viewModel = StateObject(wrappedValue: WaveformViewModel(configuration: configuration))
        
        #if DEBUG
        print("""
        🎵 EnhancedWaveform: Initializing
        - Audio Level: \(audioLevel)
        - Max Bars: \(configuration.maxBars)
        - Bar Width: \(configuration.barWidth)
        """)
        #endif
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background pulse circle
                Circle()
                    .fill(configuration.primaryColor.opacity(0.1))
                    .scaleEffect(viewModel.circleScale)
                    .opacity(Double(2 - viewModel.circleScale) / 2.0)
                    .frame(width: geometry.size.width / 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Main visualization
                HStack(spacing: configuration.spacing) {
                    ForEach(0..<configuration.maxBars, id: \.self) { index in
                        WaveformBar(
                            value: viewModel.waveforms.count > index ? viewModel.waveforms[index] : 0,
                            mirrorValue: viewModel.mirrorWaveforms.count > index ? viewModel.mirrorWaveforms[index] : 0,
                            configuration: configuration
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .onChange(of: audioLevel) { newLevel in
                #if DEBUG
                print("🎵 EnhancedWaveform: Audio level changed to \(newLevel)")
                #endif
                viewModel.updateWaveform(with: newLevel)
            }
            .onAppear {
                #if DEBUG
                print("🎵 EnhancedWaveform: View appeared")
                #endif
                viewModel.initializeWaveforms()
            }
            .onDisappear {
                #if DEBUG
                print("🎵 EnhancedWaveform: View disappeared")
                #endif
            }
        }
    }
}

// MARK: - Waveform Bar View
private struct WaveformBar: View {
    let value: CGFloat
    let mirrorValue: CGFloat
    let configuration: WaveformConfiguration
    
    var body: some View {
        VStack(spacing: 1) {
            // Upper bar
            RoundedRectangle(cornerRadius: configuration.barWidth / 2)
                .fill(
                    LinearGradient(
                        colors: [
                            configuration.primaryColor,
                            configuration.secondaryColor
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: configuration.barWidth)
                .frame(height: configuration.minBarHeight + (value * configuration.maxBarHeight))
                .animation(.easeOut(duration: configuration.animationDuration), value: value)
            
            // Lower bar (mirrored)
            RoundedRectangle(cornerRadius: configuration.barWidth / 2)
                .fill(
                    LinearGradient(
                        colors: [
                            configuration.secondaryColor,
                            configuration.primaryColor.opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: configuration.barWidth)
                .frame(height: configuration.minBarHeight + (mirrorValue * configuration.maxBarHeight))
                .animation(
                    .easeOut(duration: configuration.animationDuration)
                    .delay(0.05),
                    value: mirrorValue
                )
        }
    }
}
