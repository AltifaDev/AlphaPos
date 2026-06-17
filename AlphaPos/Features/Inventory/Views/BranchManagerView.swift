import SwiftUI
import SwiftData

struct BranchManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Branch.name) private var branches: [Branch]
    
    @State private var showingAddSheet = false
    @State private var newName = ""
    @State private var newLocation = ""
    @State private var newPhone = ""
    
    @AppStorage("active_branch_id") private var activeBranchId = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: APSpacing.lg) {
                    // Quick Info Banner
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "building.2.crop.left.back.grid")
                                .foregroundColor(.appTeal)
                            Text("branch_mgmt_title".t)
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                        }
                        Text("branch_mgmt_desc".t)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(APSpacing.md)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    // Branch List
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            ForEach(branches) { branch in
                                branchCard(branch)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("store_branches_title".t)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_btn_label".t) {
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Label("add_branch_btn".t, systemImage: "plus")
                            .foregroundColor(.appTeal)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addBranchSheet
            }
        }
        .apColorScheme()
    }
    
    @ViewBuilder
    private func branchCard(_ branch: Branch) -> some View {
        let isActive = activeBranchId == branch.id.uuidString
        
        HStack(spacing: APSpacing.md) {
            VStack(alignment: .leading, spacing: APSpacing.xs) {
                HStack(spacing: APSpacing.sm) {
                    Text(branch.name)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    
                    if isActive {
                        APBadge(text: "Active Store", color: .appTeal, icon: "checkmark.circle.fill")
                    }
                }
                
                if let loc = branch.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                
                if let phone = branch.phone, !phone.isEmpty {
                    Label(phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            
            Spacer()
            
            if !isActive {
                Button(action: {
                    activeBranchId = branch.id.uuidString
                    APHaptic.trigger()
                }) {
                    Text("branch_select_store_btn".t)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.xs)
                        .background(Color.appTeal)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(APSpacing.md)
        .background(isActive ? Color.appSurface : Color.appSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(isActive ? Color.appTeal : Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private var addBranchSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: APSpacing.lg) {
                        
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("branch_name_label".t)
                                .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal).tracking(0.5)
                            TextField("e.g., Siam Paragon, Chiang Mai Outlet", text: $newName)
                                .padding(APSpacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        }
                        
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("branch_address_label".t)
                                .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal).tracking(0.5)
                            TextField("Street address, City", text: $newLocation)
                                .padding(APSpacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        }
                        
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("branch_phone_label".t)
                                .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal).tracking(0.5)
                            TextField("Contact phone", text: $newPhone)
                                .padding(APSpacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                                .keyboardType(.phonePad)
                        }
                        
                        Text("branch_create_info_desc".t)
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                            .padding(.top, APSpacing.sm)
                        
                    }
                    .padding()
                }
            }
            .navigationTitle("create_branch_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) {
                        showingAddSheet = false
                        resetFields()
                    }
                    .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("save_btn_label".t) {
                        saveNewBranch()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.appTeal)
                    .disabled(newName.isEmpty)
                }
            }
        }
    }
    
    private func saveNewBranch() {
        let vm = InventoryViewModel(modelContext: modelContext)
        vm.addBranch(name: newName, location: newLocation.isEmpty ? nil : newLocation, phone: newPhone.isEmpty ? nil : newPhone)
        showingAddSheet = false
        resetFields()
    }
    
    private func resetFields() {
        newName = ""
        newLocation = ""
        newPhone = ""
    }
}
