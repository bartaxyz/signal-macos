import SwiftUI
import CoreImage.CIFilterBuiltins

struct LinkDeviceView: View {
    @Environment(SignalStore.self) private var store
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("Link Signal Desktop")
                .font(.largeTitle.bold())
            
            Text("Scan the QR code with your Signal mobile app")
                .foregroundStyle(.secondary)
            
            switch store.linkingState {
            case .idle:
                Button("Start Linking") {
                    store.startLinking()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .generatingQR:
                ProgressView("Generating QR code...")
                
            case .waitingForScan(let uri):
                if let qrImage = generateQRCode(from: uri) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 256, height: 256)
                        .background(Color.white)
                        .cornerRadius(12)
                } else {
                    Text("Failed to generate QR code")
                        .foregroundStyle(.red)
                }
                
                Text("Waiting for scan...")
                    .foregroundStyle(.secondary)
                
            case .linked:
                Label("Linked successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                
            case .failed(let error):
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                
                Button("Try Again") {
                    store.startLinking()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(48)
        .frame(minWidth: 400, minHeight: 500)
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let ciImage = filter.outputImage else { return nil }
        
        let scale = 10.0
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
