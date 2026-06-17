import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onScan: (String) -> Void
    
    @State private var manualBarcode = ""
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    
    // Quick simulator shortcuts for testing
    let simulatorShortcuts = [
        ("ING-BEAN", "Coffee Beans"),
        ("ING-MILK", "Fresh Milk"),
        ("ING-CHEESE", "Cheese Slice"),
        ("ING-BUN", "Burger Bun"),
        ("ING-BEEF", "Beef Patty")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0F12").ignoresSafeArea()
                
                #if targetEnvironment(simulator)
                simulatorScannerBody
                #else
                if cameraPermission == .authorized {
                    CameraScannerRepresentable(onScan: { code in
                        APHaptic.trigger()
                        onScan(code)
                        dismiss()
                    })
                    .ignoresSafeArea()
                    
                    // Scanning HUD Overlay
                    scanningOverlay
                } else if cameraPermission == .denied || cameraPermission == .restricted {
                    cameraDeniedBody
                } else {
                    Color.clear
                        .onAppear {
                            checkCameraPermission()
                        }
                }
                #endif
            }
            .navigationTitle("barcode_scanner_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) {
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }
            }
        }
        .apColorScheme()
    }
    
    // ── SIMULATOR SCANNER UI ──────────────────────────────────────────────────
    private var simulatorScannerBody: some View {
        VStack(spacing: APSpacing.xl) {
            Spacer()
            
            // Scanner visual effect box
            ZStack {
                RoundedRectangle(cornerRadius: APRadius.lg)
                    .stroke(
                        LinearGradient(colors: [.appTeal, .appAccent], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                    .frame(width: 280, height: 200)
                    .background(Color.appSurface.opacity(0.4))
                
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 60, weight: .thin))
                        .foregroundColor(.appTeal)
                    
                    Text("scanner_sim_mode".t)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    
                    Text("scanner_sim_unavailable_desc".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            
            // Manual entry
            VStack(alignment: .leading, spacing: APSpacing.xs) {
                Text("scanner_manual_entry_header".t)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.appTeal)
                    .tracking(1.0)
                
                HStack(spacing: APSpacing.sm) {
                    TextField("Enter SKU or Barcode...", text: $manualBarcode)
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                        .foregroundColor(.textPrimary)
                    
                    Button(action: {
                        if !manualBarcode.isEmpty {
                            onScan(manualBarcode)
                            dismiss()
                        }
                    }) {
                        Text("btn_scan".t)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .padding(.horizontal, APSpacing.lg)
                            .padding(.vertical, APSpacing.md)
                            .background(Color.appTeal)
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                    }
                }
            }
            .padding(.horizontal, APSpacing.xl)
            
            // Quick Shortcuts
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("scanner_quick_seed_header".t)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .tracking(0.5)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: APSpacing.sm) {
                    ForEach(simulatorShortcuts, id: \.0) { shortcut in
                        Button(action: {
                            onScan(shortcut.0)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortcut.1)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.textPrimary)
                                Text(shortcut.0)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.appTeal)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(APSpacing.md)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.sm)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, APSpacing.xl)
            
            Spacer()
        }
    }
    
    // ── CAMERA DENIED UI ──────────────────────────────────────────────────────
    private var cameraDeniedBody: some View {
        VStack(spacing: APSpacing.lg) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 64))
                .foregroundColor(.appRose)
            
            Text("scanner_camera_denied_title".t)
                .font(.title3).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            Text("scanner_camera_denied_desc".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Offer fallback text input anyway in case of permission issues
            VStack(alignment: .leading, spacing: APSpacing.xs) {
                Text("scanner_manual_fallback_header".t)
                    .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary)
                
                HStack {
                    TextField("Barcode...", text: $manualBarcode)
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                    
                    Button("submit_btn".t) {
                        if !manualBarcode.isEmpty {
                            onScan(manualBarcode)
                            dismiss()
                        }
                    }
                    .padding()
                    .background(Color.appTeal)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                }
            }
            .padding()
        }
    }
    
    // ── SCANNING HUD OVERLAY ─────────────────────────────────────────────────
    private var scanningOverlay: some View {
        VStack {
            Spacer()
            
            ZStack {
                // Outer scan framing guides
                RoundedRectangle(cornerRadius: APRadius.lg)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 280, height: 280)
                
                // Corner brackets
                Group {
                    // Top Left
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 30))
                        path.addLine(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 30, y: 0))
                    }
                    .stroke(Color.appTeal, lineWidth: 4)
                    
                    // Top Right
                    Path { path in
                        path.move(to: CGPoint(x: 250, y: 0))
                        path.addLine(to: CGPoint(x: 280, y: 0))
                        path.addLine(to: CGPoint(x: 280, y: 30))
                    }
                    .stroke(Color.appTeal, lineWidth: 4)
                    
                    // Bottom Left
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 250))
                        path.addLine(to: CGPoint(x: 0, y: 280))
                        path.addLine(to: CGPoint(x: 30, y: 280))
                    }
                    .stroke(Color.appTeal, lineWidth: 4)
                    
                    // Bottom Right
                    Path { path in
                        path.move(to: CGPoint(x: 250, y: 280))
                        path.addLine(to: CGPoint(x: 280, y: 280))
                        path.addLine(to: CGPoint(x: 280, y: 250))
                    }
                    .stroke(Color.appTeal, lineWidth: 4)
                }
                .frame(width: 280, height: 280)
                
                // Animated red scanner laser line
                ScannerLaserLine()
                    .frame(width: 260, height: 2)
            }
            .frame(width: 280, height: 280)
            
            Spacer()
            
            Text("barcode_scanner_desc".t)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.xs)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(.bottom, 40)
        }
    }
    
    // ── PERMISSIONS CHECK ─────────────────────────────────────────────────────
    private func checkCameraPermission() {
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraPermission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraPermission = granted ? .authorized : .denied
                }
            }
        }
    }
}

// ── LASER LINE ANIMATION ──────────────────────────────────────────────────────
struct ScannerLaserLine: View {
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(Color.appRose)
            .shadow(color: .appRose, radius: 4)
            .offset(y: isAnimating ? 130 : -130)
            .animation(
                Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// ── UIKIVIEWCONTROLLER REPRESENTABLE FOR AVCAPTURE ───────────────────────────
#if !targetEnvironment(simulator)
struct CameraScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    
    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let vc = CameraScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }
    
    class Coordinator: NSObject, CameraScannerDelegate {
        var onScan: (String) -> Void
        
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }
        
        func didFindBarcode(code: String) {
            onScan(code)
        }
    }
}

protocol CameraScannerDelegate: AnyObject {
    func didFindBarcode(code: String)
}

class CameraScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: CameraScannerDelegate?
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession?.canAddInput(videoInput) ?? false) {
            captureSession?.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession?.canAddOutput(metadataOutput) ?? false) {
            captureSession?.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr, .ean8, .ean13, .code128, .code39, .upce]
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if (captureSession?.isRunning ?? false) {
            captureSession?.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            // Vibrate and return code
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            delegate?.didFindBarcode(code: stringValue)
            captureSession?.stopRunning()
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}
#endif
