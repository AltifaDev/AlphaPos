// CategoryEditSheet.swift
// AlphaPos — Category Editor Sheet

import SwiftUI
import SwiftData

struct CategoryEditSheet: View {
    let category: Category? // Nil when creating new
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = InventoryViewModel()
    
    @State private var name = ""
    @State private var description = ""
    @State private var showingDeleteAlert = false
    
    var isEditing: Bool { category != nil }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("Category Information")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                    .textCase(.uppercase)
                                
                                inputFieldRow(label: "Category Name", placeholder: "e.g., Appetizers, Main Course", text: $name)
                                inputFieldRow(label: "Description (Optional)", placeholder: "e.g., Starters and light bites", text: $description)
                            }
                            .apCard()
                            
                            if isEditing {
                                deleteSectionCard
                            }
                        }
                        .padding(APSpacing.md)
                    }
                    
                    bottomActionPanel
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .onAppear {
                viewModel.modelContext = modelContext
                if let cat = category {
                    name = cat.name
                    description = cat.categoryDescription ?? ""
                }
            }
            .alert("Delete Category", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let cat = category {
                        viewModel.deleteCategory(category: cat)
                    }
                    onDismiss()
                }
            } message: {
                Text("Are you sure you want to delete this category? Products in this category will become Uncategorized.")
            }
        }
        .apColorScheme()
    }
    
    // MARK: - Subviews
    
    private var deleteSectionCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("Danger Zone")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appRose)
                .textCase(.uppercase)
            
            Text("Deleting this category will unlink all its products, making them uncategorized. This action cannot be undone.")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            
            Button(action: { showingDeleteAlert = true }) {
                Text("Delete Category")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.appRose)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var bottomActionPanel: some View {
        HStack(spacing: APSpacing.md) {
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
            
            Button(action: saveCategory) {
                Text(isEditing ? "Save Changes" : "Add Category")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(name.isEmpty ? .textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(name.isEmpty ? nil : APGradient.accent)
                    .backgroundColor(name.isEmpty ? Color.appSurfaceHigh : .clear)
                    .cornerRadius(APRadius.md)
            }
            .disabled(name.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }
    
    private func inputFieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .tint(.appAccent)
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
    }
    
    // MARK: - Save
    
    private func saveCategory() {
        if let cat = category {
            viewModel.updateCategory(
                category: cat,
                name: name,
                description: description.isEmpty ? nil : description
            )
        } else {
            viewModel.addCategory(
                name: name,
                description: description.isEmpty ? nil : description
            )
        }
        onDismiss()
    }
}
