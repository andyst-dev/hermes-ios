import AVFoundation
import SwiftUI

struct PairingQRCodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.086, green: 0.031, blue: 0.0, alpha: 1.0)
        configureCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.stopRunning()
            }
        }
    }

    private func configureCapture() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onError?("Camera unavailable")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                onError?("Camera input unavailable")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onError?("QR scanner unavailable")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
            addOverlay()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func addOverlay() {
        let border = UIView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.layer.borderWidth = 2
        border.layer.borderColor = UIColor(red: 0.851, green: 0.451, blue: 0.086, alpha: 1.0).cgColor
        border.layer.cornerRadius = 18
        view.addSubview(border)
        NSLayoutConstraint.activate([
            border.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            border.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            border.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.72),
            border.heightAnchor.constraint(equalTo: border.widthAnchor)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        hasScanned = true
        session.stopRunning()
        onCode?(value)
    }
}
