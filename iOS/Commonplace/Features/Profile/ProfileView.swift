import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSignOutAlert = false

    var body: some View {
        NavigationStack {
            List {
                // User info
                if let user = authService.currentUser {
                    Section {
                        HStack(spacing: CPSpacing.md) {
                            // Avatar
                            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(Color.cpBackgroundSecondary)
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.cpTint.opacity(0.2))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Text(String(user.fullName?.prefix(1) ?? user.email.prefix(1)))
                                            .font(.cpTitle2)
                                            .foregroundColor(.cpTint)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.fullName ?? "User")
                                    .font(.cpTitle3)

                                Text(user.email)
                                    .font(.cpSubhead)
                                    .foregroundColor(.cpTextSecondary)

                                // Subscription badge
                                HStack(spacing: 4) {
                                    Image(systemName: user.subscriptionTier == .free ? "star" : "star.fill")
                                        .font(.system(size: 10))

                                    Text(user.subscriptionTier.displayName)
                                        .font(.cpCaption1)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(user.subscriptionTier == .free ? .cpTextSecondary : .cpTint)
                            }
                        }
                        .padding(.vertical, CPSpacing.xs)
                    }
                }

                // Stats - Now using real data!
                Section("Library Stats") {
                    StatsRow(icon: "doc.text", title: "Documents Saved", value: "\(viewModel.documentCount)")
                    StatsRow(icon: "clock", title: "Total Reading Time", value: viewModel.formattedReadingTime)
                    StatsRow(icon: "calendar", title: "This Week", value: "\(viewModel.documentsThisWeek) saved")
                }

                // Weekly Summary
                Section("Weekly Summary") {
                    NavigationLink {
                        WeeklySummaryView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .foregroundColor(.purple)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Reading Insights")
                                    .font(.cpBody)
                                Text("See what you read this week")
                                    .font(.cpCaption1)
                                    .foregroundColor(.cpTextSecondary)
                            }
                        }
                    }
                }

                // Settings
                Section("Settings") {
                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        SettingsRow(icon: "bell", title: "Notifications")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsRow(icon: "paintbrush", title: "Appearance")
                    }

                    NavigationLink {
                        CategoriesSettingsView(categories: $viewModel.categories)
                    } label: {
                        SettingsRow(icon: "folder", title: "Manage Categories")
                    }
                }

                // Subscription
                Section("Subscription") {
                    if authService.currentUser?.subscriptionTier == .free {
                        Button {
                            // Show upgrade sheet
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Upgrade to Pro")
                                        .font(.cpHeadline)
                                        .foregroundColor(.cpText)

                                    Text("Unlimited saves, AI features & more")
                                        .font(.cpFootnote)
                                        .foregroundColor(.cpTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.cpTextTertiary)
                            }
                        }
                    } else {
                        NavigationLink {
                            Text("Subscription Management")
                        } label: {
                            SettingsRow(icon: "creditcard", title: "Manage Subscription")
                        }
                    }
                }

                // Support
                Section("Support") {
                    Button {
                        if let url = URL(string: "mailto:support@commonplace.app") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingsRow(icon: "envelope", title: "Contact Support")
                    }

                    NavigationLink {
                        Text("FAQ")
                    } label: {
                        SettingsRow(icon: "questionmark.circle", title: "FAQ")
                    }

                    NavigationLink {
                        Text("Privacy Policy")
                    } label: {
                        SettingsRow(icon: "lock.shield", title: "Privacy Policy")
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        showingSignOutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }

                // App version
                Section {
                    HStack {
                        Spacer()
                        Text("Commonplace v1.0.0")
                            .font(.cpCaption1)
                            .foregroundColor(.cpTextTertiary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Profile")
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    authService.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .task {
                await viewModel.loadStats()
            }
        }
    }
}

// MARK: - Profile ViewModel

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var documentCount: Int = 0
    @Published var totalReadingMinutes: Int = 0
    @Published var documentsThisWeek: Int = 0
    @Published var categories: [Category] = Category.systemCategories
    @Published var weeklyDocuments: [Document] = []
    @Published var topCategories: [String] = []
    @Published var topTopics: [String] = []

    private let documentService = DocumentService.shared

    var formattedReadingTime: String {
        if totalReadingMinutes == 0 {
            return "0m"
        } else if totalReadingMinutes < 60 {
            return "\(totalReadingMinutes)m"
        } else {
            let hours = totalReadingMinutes / 60
            let minutes = totalReadingMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }

    var weeklyReadingMinutes: Int {
        weeklyDocuments.compactMap { $0.readingTimeMinutes }.reduce(0, +)
    }

    var formattedWeeklyReadingTime: String {
        let minutes = weeklyReadingMinutes
        if minutes == 0 {
            return "0m"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }

    func loadStats() async {
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        // Check if demo mode
        if AuthService.shared.currentUser?.email == "demo@commonplace.app" {
            let demoDocuments = documentService.fetchDemoDocuments()
            documentCount = demoDocuments.count
            totalReadingMinutes = demoDocuments.compactMap { $0.readingTimeMinutes }.reduce(0, +)

            weeklyDocuments = demoDocuments.filter { $0.createdAt > oneWeekAgo }
            documentsThisWeek = weeklyDocuments.count

            // Calculate top categories
            let categoryCounts = demoDocuments.flatMap { $0.userCategories }
                .reduce(into: [:]) { counts, cat in counts[cat, default: 0] += 1 }
            topCategories = categoryCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

            // Calculate top topics
            let topicCounts = demoDocuments.flatMap { $0.aiTopics ?? [] }
                .reduce(into: [:]) { counts, topic in counts[topic, default: 0] += 1 }
            topTopics = topicCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        } else {
            // Real mode - fetch from API
            do {
                let stats = try await documentService.fetchStats()
                documentCount = stats.totalDocuments
                totalReadingMinutes = stats.totalReadTime
                documentsThisWeek = stats.documentsThisWeek
                topCategories = stats.topCategories
            } catch {
                print("Failed to load stats: \(error)")
            }
        }
    }
}

// MARK: - Stats Row

struct StatsRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cpTint)
                .frame(width: 24)

            Text(title)
                .font(.cpBody)

            Spacer()

            Text(value)
                .font(.cpBody)
                .foregroundColor(.cpTextSecondary)
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cpTint)
                .frame(width: 24)

            Text(title)
                .font(.cpBody)
                .foregroundColor(.cpText)
        }
    }
}

// MARK: - Settings Views

struct NotificationsSettingsView: View {
    @State private var newArticleAlerts = true
    @State private var weeklyDigest = true
    @State private var readingReminders = false

    var body: some View {
        List {
            Section("Alerts") {
                Toggle("New Article Processed", isOn: $newArticleAlerts)
                Toggle("Weekly Reading Digest", isOn: $weeklyDigest)
                Toggle("Reading Reminders", isOn: $readingReminders)
            }

            Section(footer: Text("Notifications help you stay on top of your reading list.")) {
                EmptyView()
            }
        }
        .navigationTitle("Notifications")
    }
}

struct AppearanceSettingsView: View {
    @State private var selectedTheme = 0

    var body: some View {
        List {
            Section("Theme") {
                Picker("App Theme", selection: $selectedTheme) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Section("Reading") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("Medium")
                        .foregroundColor(.cpTextSecondary)
                }

                HStack {
                    Text("Line Spacing")
                    Spacer()
                    Text("Normal")
                        .foregroundColor(.cpTextSecondary)
                }
            }
        }
        .navigationTitle("Appearance")
    }
}

struct CategoriesSettingsView: View {
    @Binding var categories: [Category]
    @State private var newCategoryName = ""
    @State private var showingAddCategory = false

    var body: some View {
        List {
            Section("Your Categories") {
                ForEach(categories) { category in
                    HStack {
                        Text(category.icon ?? "📁")
                        Text(category.name)
                        Spacer()
                        if category.isSystem {
                            Text("System")
                                .font(.cpCaption1)
                                .foregroundColor(.cpTextTertiary)
                        }
                    }
                }
                .onDelete { indexSet in
                    categories.remove(atOffsets: indexSet)
                }
            }

            Section {
                Button {
                    showingAddCategory = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.cpTint)
                        Text("Add Category")
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .alert("Add Category", isPresented: $showingAddCategory) {
            TextField("Category Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
            Button("Add") {
                if !newCategoryName.isEmpty {
                    let newCategory = Category(
                        id: UUID(),
                        userId: AuthService.shared.currentUser?.id,
                        name: newCategoryName,
                        slug: newCategoryName.lowercased().replacingOccurrences(of: " ", with: "-"),
                        icon: "📁",
                        color: "#007AFF",
                        isSystem: false,
                        sortOrder: categories.count
                    )
                    categories.append(newCategory)
                    newCategoryName = ""
                }
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthService.shared)
}

// MARK: - Weekly Summary

struct WeeklySummaryView: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        List {
            Section("This Week") {
                StatsRow(icon: "doc.text", title: "Saved", value: "\(viewModel.documentsThisWeek)")
                StatsRow(icon: "clock", title: "Reading Time", value: "\(viewModel.totalReadingMinutes) min")
            }

            if !viewModel.topCategories.isEmpty {
                Section("Top Categories") {
                    ForEach(viewModel.topCategories, id: \.self) { category in
                        Text(category)
                            .font(.cpBody)
                    }
                }
            }

            if !viewModel.topTopics.isEmpty {
                Section("Top Topics") {
                    ForEach(viewModel.topTopics, id: \.self) { topic in
                        Text(topic)
                            .font(.cpBody)
                    }
                }
            }

            Section("Saved This Week") {
                if viewModel.weeklyDocuments.isEmpty {
                    Text("Nothing saved yet this week")
                        .font(.cpBody)
                        .foregroundColor(.cpTextSecondary)
                } else {
                    ForEach(viewModel.weeklyDocuments) { document in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title)
                                .font(.cpBody)
                                .lineLimit(2)
                            Text("\(document.sourceType.displayName) · \(document.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.cpCaption1)
                                .foregroundColor(.cpTextSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Weekly Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadStats()
        }
    }
}
