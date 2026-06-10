import SwiftUI
import SwiftData

struct BatchQRCodePrintView: View {
    let tables: [RestaurantTable]
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
    @Environment(\.dismiss) private var dismiss
    
    @State private var zoomedTable: RestaurantTable? = nil
    
    // Grid layout for 3 columns on A4 width
    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]
    
    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("A4 Grid Layout Preview (3 Columns) - Tap any QR Code to zoom")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(tables) { table in
                                VStack(spacing: 8) {
                                    Text("Table \(table.tableNumber)")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.textPrimary)
                                    
                                    let qrUrl = "https://alphapos.altifadev.workers.dev/?table=\(table.tableNumber)&merchant=\(activeMerchantId)"
                                    
                                    if let qrImage = generateQRCode(from: qrUrl) {
                                        Image(uiImage: qrImage)
                                            .resizable()
                                            .interpolation(.none)
                                            .frame(width: 140, height: 140)
                                            .padding(8)
                                            .background(Color.white)
                                            .cornerRadius(8)
                                            .shadow(color: Color.black.opacity(0.08), radius: 3)
                                    } else {
                                        Image(systemName: "qrcode")
                                            .resizable()
                                            .frame(width: 140, height: 140)
                                            .foregroundColor(.appBorderSubtle)
                                    }
                                    
                                    Text("table=\(table.tableNumber)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(1)
                                        .padding(.top, 2)
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 10)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    zoomedTable = table
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .background(Color.appBackground)
                .navigationTitle("All Table QR Codes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            exportToPDF()
                        }) {
                            Label("Export PDF", systemImage: "doc.plaintext.fill")
                                .foregroundColor(.appAccent)
                        }
                    }
                }
            }
            
            // Zoomed overlay presentation
            if let table = zoomedTable {
                zoomedOverlay(for: table)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: zoomedTable != nil)
    }
    
    /// Generates high-quality CIQRCode Image
    private func generateQRCode(from string: String) -> UIImage? {
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            if let output = filter.outputImage?.transformed(by: transform) {
                let context = CIContext()
                if let cgImage = context.createCGImage(output, from: output.extent) {
                    return UIImage(cgImage: cgImage)
                }
            }
        }
        return nil
    }
    
    /// Zoomed Single Table QR Code Overlay
    @ViewBuilder
    private func zoomedOverlay(for table: RestaurantTable) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    zoomedTable = nil
                }
            
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: {
                        zoomedTable = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("Table \(table.tableNumber)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                let qrUrl = "https://alphapos.altifadev.workers.dev/?table=\(table.tableNumber)&merchant=\(activeMerchantId)"
                
                if let qrImage = generateQRCode(from: qrUrl) {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.12), radius: 8)
                }
                
                VStack(spacing: 8) {
                    Text("Self-Ordering URL:")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    
                    Text(qrUrl)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.appAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .lineLimit(2)
                    
                    Button(action: {
                        UIPasteboard.general.string = qrUrl
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Link")
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.appAccent.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(width: 380)
            .background(Color.appSurface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.25), radius: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
    }
    
    /// Generates and shares A4 formatted PDF
    private func exportToPDF() {
        // A4 page size in points: 595.2 width x 841.8 height
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595.2, height: 841.8))
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AlphaPos_Table_QRCodes.pdf")
        
        do {
            try pdfRenderer.writePDF(to: url) { context in
                // Grid calculation settings (3 columns x 4 rows = 12 QR codes per A4 page)
                let itemsPerPage = 12
                let totalPages = Int(ceil(Double(tables.count) / Double(itemsPerPage)))
                
                for pageIndex in 0..<totalPages {
                    context.beginPage()
                    
                    // Header text
                    let title = "AlphaPos - Table Self-Ordering QR Codes"
                    let font = UIFont.boldSystemFont(ofSize: 16)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: UIColor.black
                    ]
                    title.draw(at: CGPoint(x: 36, y: 36), withAttributes: attributes)
                    
                    // Draw separator line under header
                    let drawContext = context.cgContext
                    drawContext.setStrokeColor(UIColor.lightGray.cgColor)
                    drawContext.setLineWidth(0.5)
                    drawContext.move(to: CGPoint(x: 36, y: 58))
                    drawContext.addLine(to: CGPoint(x: 559.2, y: 58))
                    drawContext.strokePath()
                    
                    let startX: CGFloat = 36
                    let startY: CGFloat = 80
                    let colWidth: CGFloat = (595.2 - 72) / 3
                    let rowHeight: CGFloat = (841.8 - 120) / 4
                    
                    let startIndex = pageIndex * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, tables.count)
                    
                    for index in startIndex..<endIndex {
                        let table = tables[index]
                        let itemIndex = index - startIndex
                        
                        let col = CGFloat(itemIndex % 3)
                        let row = CGFloat(itemIndex / 3)
                        
                        let x = startX + col * colWidth
                        let y = startY + row * rowHeight
                        
                        // Draw box/card borders
                        let cardRect = CGRect(x: x + 5, y: y + 5, width: colWidth - 10, height: rowHeight - 10)
                        drawContext.setFillColor(UIColor(white: 0.98, alpha: 1.0).cgColor)
                        drawContext.fill(cardRect)
                        drawContext.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
                        drawContext.setLineWidth(1.0)
                        
                        // Rounded rectangle for card border
                        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
                        path.stroke()
                        
                        // Table Number text
                        let tableName = "Table \(table.tableNumber)"
                        let nameFont = UIFont.boldSystemFont(ofSize: 13)
                        tableName.draw(at: CGPoint(x: x + 20, y: y + 20), withAttributes: [.font: nameFont, .foregroundColor: UIColor.black])
                        
                        // Generate QR Code image and draw it inside card
                        let qrUrl = "https://alphapos.altifadev.workers.dev/?table=\(table.tableNumber)&merchant=\(activeMerchantId)"
                        if let qrImage = generateQRCode(from: qrUrl) {
                            qrImage.draw(in: CGRect(x: x + (colWidth - 100) / 2, y: y + 45, width: 100, height: 100))
                        }
                        
                        // Link text
                        let linkText = "Scan to Order"
                        let linkFont = UIFont.systemFont(ofSize: 9)
                        let linkAttributes: [NSAttributedString.Key: Any] = [
                            .font: linkFont,
                            .foregroundColor: UIColor.darkGray
                        ]
                        linkText.draw(at: CGPoint(x: x + (colWidth - linkText.size(withAttributes: linkAttributes).width) / 2, y: y + 155), withAttributes: linkAttributes)
                    }
                    
                    // Footer text
                    let footerText = "Page \(pageIndex + 1) of \(totalPages)"
                    let footerFont = UIFont.systemFont(ofSize: 8)
                    let footerAttributes: [NSAttributedString.Key: Any] = [
                        .font: footerFont,
                        .foregroundColor: UIColor.gray
                    ]
                    footerText.draw(at: CGPoint(x: 559.2 - footerText.size(withAttributes: footerAttributes).width, y: 810), withAttributes: footerAttributes)
                }
            }
            
            // Present Activity Sheet
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = rootVC.view
                    popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                rootVC.present(activityVC, animated: true)
            }
            
        } catch {
            print("Failed to write PDF: \(error)")
        }
    }
}
