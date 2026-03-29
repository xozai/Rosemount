// PhotoEditView.swift
// Rosemount
//
// Basic photo editing view with brightness/contrast/saturation sliders and CIFilter presets.

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - PhotoFilter

enum PhotoFilter: String, CaseIterable, Identifiable {
    case none
    case mono
    case fade
    case chrome
    case noir
    case vivid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "None"
        case .mono:   return "Mono"
        case .fade:   return "Fade"
        case .chrome: return "Chrome"
        case .noir:   return "Noir"
        case .vivid:  return "Vivid"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none:   return "circle.slash"
        case .mono:   return "camera.filters"
        case .fade:   return "sun.haze"
        case .chrome: return "circle.hexagonpath"
        case .noir:   return "moon.stars"
        case .vivid:  return "sparkles"
        }
    }

    /// Returns the name of the CIFilter to apply, or nil for .none.
    var ciFilterName: String? {
        switch self {
        case .none:   return nil
        case .mono:   return "CIPhotoEffectMono"
        case .fade:   return "CIPhotoEffectFade"
        case .chrome: return "CIPhotoEffectChrome"
        case .noir:   return "CIPhotoEffectNoir"
        case .vivid:  return "CIPhotoEffectTransfer"
        }
    }
}

// MARK: - PhotoEditView

struct PhotoEditView: View {
    let originalImage: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var saturation: Double = 1.0
    @State private var selectedFilter: PhotoFilter = .none

    @State private var processedImage: UIImage?
    @State private var isProcessing = false

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(image: UIImage, onSave: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.originalImage = image
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var displayImage: UIImage {
        processedImage ?? originalImage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: Image Preview
                GeometryReader { geo in
                    ZStack {
                        Color.black

                        Image(uiImage: displayImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                // MARK: Filter Row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(PhotoFilter.allCases) { filter in
                            Button {
                                selectedFilter = filter
                                scheduleProcessing()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: filter.sfSymbol)
                                        .font(.system(size: 22))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            selectedFilter == filter
                                                ? Color.blue.opacity(0.2)
                                                : Color.clear
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(
                                            selectedFilter == filter ? .blue : .primary
                                        )

                                    Text(filter.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(
                                            selectedFilter == filter ? .blue : .secondary
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial)

                Divider()

                // MARK: Sliders
                VStack(spacing: 16) {
                    AdjustmentSlider(
                        label: "Brightness",
                        systemImage: "sun.max",
                        value: $brightness,
                        range: -1.0...1.0,
                        defaultValue: 0.0
                    )
                    .onChange(of: brightness) { _, _ in scheduleProcessing() }

                    AdjustmentSlider(
                        label: "Contrast",
                        systemImage: "circle.lefthalf.filled",
                        value: $contrast,
                        range: 0.5...1.5,
                        defaultValue: 1.0
                    )
                    .onChange(of: contrast) { _, _ in scheduleProcessing() }

                    AdjustmentSlider(
                        label: "Saturation",
                        systemImage: "paintpalette",
                        value: $saturation,
                        range: 0.0...2.0,
                        defaultValue: 1.0
                    )
                    .onChange(of: saturation) { _, _ in scheduleProcessing() }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayImage)
                    }
                    .fontWeight(.semibold)
                    .disabled(isProcessing)
                }
            }
        }
        .onAppear {
            scheduleProcessing()
        }
    }

    // MARK: - Image Processing

    private func scheduleProcessing() {
        Task {
            await applyFilters()
        }
    }

    @MainActor
    private func applyFilters() async {
        isProcessing = true
        defer { isProcessing = false }

        let result = await Task.detached(priority: .userInitiated) { [
            originalImage,
            brightness,
            contrast,
            saturation,
            selectedFilter,
            ciContext
        ] () -> UIImage? in
            return Self.render(
                image: originalImage,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                filter: selectedFilter,
                context: ciContext
            )
        }.value

        if let result {
            processedImage = result
        }
    }

    private static func render(
        image: UIImage,
        brightness: Double,
        contrast: Double,
        saturation: Double,
        filter: PhotoFilter,
        context: CIContext
    ) -> UIImage? {
        guard var ciImage = CIImage(image: image) else { return nil }

        // Apply colour adjustment
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        colorControls.saturation = Float(saturation)

        guard let adjusted = colorControls.outputImage else { return nil }
        ciImage = adjusted

        // Apply named filter preset
        if let filterName = filter.ciFilterName,
           let preset = CIFilter(name: filterName) {
            preset.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = preset.outputImage {
                ciImage = output
            }
        }

        // Render to CGImage
        let extent = ciImage.extent
        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - AdjustmentSlider

private struct AdjustmentSlider: View {
    let label: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label(label, systemImage: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)

                Button {
                    value = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .opacity(value == defaultValue ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: value == defaultValue)
            }

            Slider(value: $value, in: range)
                .tint(.blue)
        }
    }
}

#Preview {
    PhotoEditView(
        image: UIImage(systemName: "photo")!,
        onSave: { _ in },
        onCancel: {}
    )
}
