//
//  PromotionsManagementView.swift
//  AlphaPos
//
//  Created by Antigravity on 2026-06-08.
//

import SwiftUI
import SwiftData
import PhotosUI

struct PromotionsManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Promotion> { $0.isDeleted == false }, sort: \Promotion.updatedAt, order: .reverse) private var promotions: [Promotion]
    
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    @State private var showingAddSheet = false
    @State private var promotionToEdit: Promotion? = nil
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerView
                    
                    if promotions.isEmpty {
                        emptyStateView
                    } else {
                        promotionsGridView
                    }
                }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddSheet) {
            PromotionFormSheet(promotion: nil)
        }
        .sheet(item: $promotionToEdit) { promotion in
            PromotionFormSheet(promotion: promotion)
        }
        .onAppear {
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 16) {
            if columnVisibility == .detailOnly {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = .all
                    }
                    APHaptic.trigger()
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.appAccent)
                        .padding(10)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage Promotions")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text("Configure banner ads and promotions displayed on the customer self-ordering web app.")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            
            Button(action: { showingAddSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add Promotion")
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color(hex: "10B981").opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 80, height: 80)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "10B981"))
            }
            
            VStack(spacing: 8) {
                Text("No Promotions Found")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text("Tap 'Add Promotion' to create a new banner advertisement or product promotion.")
                    .font(.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var promotionsGridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 24) {
                ForEach(promotions) { promo in
                    promotionCard(for: promo)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    @ViewBuilder
    private func promotionCard(for promo: Promotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner Preview
            ZStack {
                if let base64 = promo.imageData,
                   let data = Data(base64Encoded: base64),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color.appSurfaceHigh, Color.appSurface], startPoint: .top, endPoint: .bottom)
                        .frame(height: 180)
                    
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.textTertiary)
                }
                
                // Status Badge Overlay
                VStack {
                    HStack {
                        Spacer()
                        Text(promo.isActive ? "Active" : "Inactive")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(promo.isActive ? Color.appTeal : Color.gray)
                            .cornerRadius(8)
                            .shadow(radius: 4)
                    }
                    Spacer()
                }
                .padding(12)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 8) {
                Text(promo.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                
                if let desc = promo.promoDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .frame(minHeight: 36, alignment: .topLeading)
                } else {
                    Text("No description provided")
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                        .frame(minHeight: 36, alignment: .topLeading)
                }
                
                Divider()
                    .background(Color.appDivider)
                    .padding(.vertical, 4)
                
                HStack {
                    // Sync Status Indicator
                    HStack(spacing: 4) {
                        Image(systemName: promo.isSynced ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(promo.isSynced ? .appTeal : .orange)
                        Text(promo.isSynced ? "Synced" : "Unsynced")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation {
                                promo.isActive.toggle()
                                promo.isSynced = false
                                promo.updatedAt = Date()
                                try? modelContext.save()
                                
                                // Trigger sync in the background
                                Task {
                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                                }
                            }
                        }) {
                            Image(systemName: promo.isActive ? "eye.slash" : "eye")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }
                        
                        Button(action: { promotionToEdit = promo }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }
                        
                        Button(action: {
                            deletePromotion(promo)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .foregroundColor(.appRose)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.appSurface)
        }
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func deletePromotion(_ promo: Promotion) {
        withAnimation {
            promo.isDeleted = true
            promo.isSynced = false
            promo.updatedAt = Date()
            try? modelContext.save()
            
            // Trigger sync in the background
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }
}

struct PromotionFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let promotion: Promotion?
    
    @State private var title: String = ""
    @State private var promoDescription: String = ""
    @State private var imageDataBase64: String? = nil
    @State private var isActive: Bool = true
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isProcessingImage = false
    
    var isNew: Bool { promotion == nil }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Promotion Information")) {
                    TextField("Promotion Title", text: $title)
                        .foregroundColor(.textPrimary)
                    
                    TextField("Description", text: $promoDescription, axis: .vertical)
                        .lineLimit(3...5)
                        .foregroundColor(.textPrimary)
                    
                    Toggle("Active Status", isOn: $isActive)
                        .tint(Color(hex: "10B981"))
                }
                
                Section(header: Text("Banner Image (Recommended size: 800 x 400 px)")) {
                    VStack(spacing: 12) {
                        if isProcessingImage {
                            ProgressView("Processing image...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if let base64 = imageDataBase64,
                                  let data = Data(base64Encoded: base64),
                                  let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 180)
                                .cornerRadius(8)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 40))
                                    .foregroundColor(.textTertiary)
                                Text("No Image Selected")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(8)
                        }
                        
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            HStack {
                                Image(systemName: "photo")
                                Text(imageDataBase64 == nil ? "Select Image" : "Change Image")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(isNew ? "Add New Promotion" : "Edit Promotion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePromotion()
                    }
                    .disabled(title.isEmpty || isProcessingImage)
                    .foregroundColor(title.isEmpty || isProcessingImage ? .textTertiary : Color(hex: "10B981"))
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    guard let item = newItem else { return }
                    await MainActor.run { isProcessingImage = true }
                    
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        // Downscale to max 800 width while maintaining aspect ratio
                        let resized = resizeImage(image: image, targetSize: CGSize(width: 800, height: 400))
                        if let jpeg = resized.jpegData(compressionQuality: 0.7) {
                            let base64 = jpeg.base64EncodedString()
                            await MainActor.run {
                                self.imageDataBase64 = base64
                                self.isProcessingImage = false
                            }
                            return
                        }
                    }
                    await MainActor.run { isProcessingImage = false }
                }
            }
            .onAppear {
                if let promo = promotion {
                    title = promo.title
                    promoDescription = promo.promoDescription ?? ""
                    imageDataBase64 = promo.imageData
                    isActive = promo.isActive
                }
            }
        }
    }
    
    private func savePromotion() {
        if let promo = promotion {
            // Edit existing
            promo.title = title
            promo.promoDescription = promoDescription
            promo.imageData = imageDataBase64
            promo.isActive = isActive
            promo.isSynced = false
            promo.updatedAt = Date()
        } else {
            // Create new
            let newPromo = Promotion(
                title: title,
                promoDescription: promoDescription,
                imageData: imageDataBase64,
                isActive: isActive
            )
            modelContext.insert(newPromo)
        }
        
        try? modelContext.save()
        
        // Trigger sync in the background
        let context = modelContext
        Task {
            await SyncEngine.shared.syncAll(modelContext: context)
        }
        
        dismiss()
    }
    
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        let newRatio = min(widthRatio, heightRatio)
        
        // If image is already smaller, don't upscale it
        if newRatio >= 1.0 {
            return image
        }
        
        let newSize = CGSize(width: size.width * newRatio, height: size.height * newRatio)
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
}
