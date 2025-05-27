// File: Components/Interactive/InteractiveComponents.swift

import SwiftUI
import AVKit
import Combine

// MARK: - Audio Player Controls
struct AudioPlayerControls: View {
    let duration: TimeInterval
    @Binding var currentTime: TimeInterval
    @Binding var isPlaying: Bool
    @Binding var playbackRate: Float
    let onSeek: (TimeInterval) -> Void
    
    private let playbackRates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
    
    init(
        duration: TimeInterval,
        currentTime: Binding<TimeInterval>,
        isPlaying: Binding<Bool>,
        playbackRate: Binding<Float>,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.duration = duration
        self._currentTime = currentTime
        self._isPlaying = isPlaying
        self._playbackRate = playbackRate
        self.onSeek = onSeek
        
        #if DEBUG
        print("🎵 AudioPlayer: Creating controls with duration: \(duration)")
        #endif
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Time Slider
            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { onSeek($0) }
                ),
                in: 0...duration
            ) {
                Text("Time Slider")
            } minimumValueLabel: {
                Text(formatTime(currentTime))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            } maximumValueLabel: {
                Text(formatTime(duration))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .tint(Theme.Colors.primary)
            
            // Controls
            HStack(spacing: Theme.Spacing.lg) {
                Button(action: {
                    #if DEBUG
                    print("🎵 AudioPlayer: Skip backward")
                    #endif
                    onSeek(max(0, currentTime - 15))
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                
                Button(action: {
                    #if DEBUG
                    print("🎵 AudioPlayer: Play/Pause toggled to: \(!isPlaying)")
                    #endif
                    isPlaying.toggle()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                
                Button(action: {
                    #if DEBUG
                    print("🎵 AudioPlayer: Skip forward")
                    #endif
                    onSeek(min(duration, currentTime + 15))
                }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                
                Menu {
                    ForEach(playbackRates, id: \.self) { rate in
                        Button(action: {
                            #if DEBUG
                            print("🎵 AudioPlayer: Playback rate changed to: \(rate)")
                            #endif
                            playbackRate = rate
                        }) {
                            HStack {
                                Text("\(String(format: "%.2fx", rate))")
                                if abs(playbackRate - rate) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(String(format: "%.2fx", playbackRate))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.primary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Theme.Colors.primary.opacity(0.1))
                        .cornerRadius(Theme.Layout.cornerRadius)
                }
            }
        }
        .padding(Theme.Spacing.md)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Swipeable Card
struct SwipeableCard<Content: View>: View {
    let content: Content
    let onSwipeLeft: (() -> Void)?
    let onSwipeRight: (() -> Void)?
    let leftActionColor: Color
    let rightActionColor: Color
    let leftActionIcon: String
    let rightActionIcon: String
    
    @GestureState private var translation: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var previousOffset: CGFloat = 0
    
    private let swipeThreshold: CGFloat = 50
    
    init(
        @ViewBuilder content: () -> Content,
        onSwipeLeft: (() -> Void)? = nil,
        onSwipeRight: (() -> Void)? = nil,
        leftActionColor: Color = Theme.Colors.error,
        rightActionColor: Color = Theme.Colors.success,
        leftActionIcon: String = "trash.fill",
        rightActionIcon: String = "star.fill"
    ) {
        self.content = content()
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.leftActionColor = leftActionColor
        self.rightActionColor = rightActionColor
        self.leftActionIcon = leftActionIcon
        self.rightActionIcon = rightActionIcon
        
        #if DEBUG
        print("🎴 SwipeableCard: Creating new card")
        #endif
    }
    
    var body: some View {
        ZStack {
            // Background actions
            HStack {
                if onSwipeLeft != nil {
                    leftActionIndicator
                }
                
                Spacer()
                
                if onSwipeRight != nil {
                    rightActionIndicator
                }
            }
            
            // Card content
            content
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .updating($translation) { value, state, _ in
                            state = value.translation.width
                        }
                        .onChanged { value in
                            offset = previousOffset + value.translation.width
                        }
                        .onEnded { value in
                            handleSwipeEnd(with: value)
                        }
                )
        }
    }
    
    private var leftActionIndicator: some View {
        Image(systemName: leftActionIcon)
            .font(.title2)
            .foregroundColor(.white)
            .frame(width: 80)
            .background(leftActionColor)
            .opacity(offset < 0 ? 1 : 0)
    }
    
    private var rightActionIndicator: some View {
        Image(systemName: rightActionIcon)
            .font(.title2)
            .foregroundColor(.white)
            .frame(width: 80)
            .background(rightActionColor)
            .opacity(offset > 0 ? 1 : 0)
    }
    
    private func handleSwipeEnd(with value: DragGesture.Value) {
        let swipeDistance = value.translation.width + previousOffset
        
        if abs(swipeDistance) > swipeThreshold {
            if swipeDistance > 0 && onSwipeRight != nil {
                #if DEBUG
                print("🎴 SwipeableCard: Right swipe action triggered")
                #endif
                withAnimation(.spring()) {
                    offset = 80
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onSwipeRight?()
                        offset = 0
                    }
                }
            } else if swipeDistance < 0 && onSwipeLeft != nil {
                #if DEBUG
                print("🎴 SwipeableCard: Left swipe action triggered")
                #endif
                withAnimation(.spring()) {
                    offset = -80
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onSwipeLeft?()
                        offset = 0
                    }
                }
            } else {
                withAnimation(.spring()) {
                    offset = 0
                }
            }
        } else {
            withAnimation(.spring()) {
                offset = 0
            }
        }
        previousOffset = offset
    }
}

// MARK: - Selection Controls
struct SelectionControl: View {
    enum SelectionStyle {
        case radio
        case checkbox
        case toggle
    }
    
    let title: String
    let subtitle: String?
    let style: SelectionStyle
    @Binding var isSelected: Bool
    let action: (() -> Void)?
    
    init(
        title: String,
        subtitle: String? = nil,
        style: SelectionStyle = .checkbox,
        isSelected: Binding<Bool>,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self._isSelected = isSelected
        self.action = action
        
        #if DEBUG
        print("✅ SelectionControl: Creating control with title: \(title), style: \(style)")
        #endif
    }
    
    var body: some View {
        Button(action: {
            #if DEBUG
            print("✅ SelectionControl: Selection changed for '\(title)' to: \(!isSelected)")
            #endif
            isSelected.toggle()
            action?()
        }) {
            HStack(spacing: Theme.Spacing.md) {
                // Selection indicator
                Group {
                    switch style {
                    case .radio:
                        Circle()
                            .stroke(Theme.Colors.primary, lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .fill(Theme.Colors.primary)
                                    .frame(width: 16, height: 16)
                                    .opacity(isSelected ? 1 : 0)
                            )
                    case .checkbox:
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.secondaryText)
                            .font(.title3)
                    case .toggle:
                        Toggle("", isOn: $isSelected)
                            .labelsHidden()
                            .tint(Theme.Colors.primary)
                    }
                }
                .animation(.spring(), value: isSelected)
                
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.text)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Color Picker
struct CustomColorPicker: View {
    @Binding var selectedColor: Color
    let colors: [Color]
    
    init(
        selectedColor: Binding<Color>,
        colors: [Color] = [
            .red, .orange, .yellow, .green,
            .blue, .purple, .pink, .gray
        ]
    ) {
        self._selectedColor = selectedColor
        self.colors = colors
        
        #if DEBUG
        print("🎨 ColorPicker: Creating picker with \(colors.count) colors")
        #endif
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(colors, id: \.self) { color in
                    ColorButton(
                        color: color,
                        isSelected: color == selectedColor
                    ) {
                        #if DEBUG
                        print("🎨 ColorPicker: Color selected: \(color)")
                        #endif
                        withAnimation(.spring()) {
                            selectedColor = color
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
}

private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                )
                .shadow(color: color.opacity(0.3),
                        radius: isSelected ? 4 : 2,
                        x: 0, y: 2)
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(), value: isSelected)
    }
}

// MARK: - Preview Provider
#if DEBUG
struct InteractiveComponents_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Audio Player Preview
            AudioPlayerControls(
                duration: 180,
                currentTime: .constant(45),
                isPlaying: .constant(true),
                playbackRate: .constant(1.0)
            ) { _ in }
            .previewDisplayName("Audio Player")
            
            // Swipeable Card Preview
            SwipeableCard(
                content: {
                    Text("Swipe me!")
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(Theme.Colors.background)
                },
                onSwipeLeft: { print("Left swipe") },
                onSwipeRight: { print("Right swipe") }
            )
            .previewDisplayName("Swipeable Card")
            
            // Selection Controls Preview
            VStack(spacing: Theme.Spacing.md) {
                SelectionControl(
                    title: "Checkbox Option",
                    subtitle: "With subtitle",
                    style: .checkbox,
                    isSelected: .constant(true)
                )
                
                SelectionControl(
                    title: "Radio Option",
                    style: .radio,
                    isSelected: .constant(false)
                )
                
                SelectionControl(
                    title: "Toggle Option",
                    style: .toggle,
                    isSelected: .constant(true)
                )
            }
            .padding()
            .previewDisplayName("Selection Controls")
            
            // Color Picker Preview
            CustomColorPicker(selectedColor: .constant(.blue))
                .padding()
                .previewDisplayName("Color Picker")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
