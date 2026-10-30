import SwiftUI
import Charts

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSignOutAlert = false
    @State private var showingContactOptions = false
    @State private var showingCopiedAddress = false
    @State private var showingDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: Error?

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
                    StatsRow(icon: "clock", title: "Est. Reading Time", value: viewModel.formattedReadingTime)
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
                                Text("See what you saved this week")
                                    .font(.cpCaption1)
                                    .foregroundColor(.cpTextSecondary)
                            }
                        }
                    }
                }

                // Settings
                Section("Settings") {
                    NavigationLink {
                        CategoriesSettingsView()
                    } label: {
                        SettingsRow(icon: "folder", title: "Manage Categories")
                    }
                }

                // Support
                Section("Support") {
                    Button {
                        showingContactOptions = true
                    } label: {
                        SettingsRow(icon: "envelope", title: "Contact Support")
                    }
                    .foregroundColor(.cpText)

                    NavigationLink {
                        FAQView()
                    } label: {
                        SettingsRow(icon: "questionmark.circle", title: "FAQ")
                    }

                    NavigationLink {
                        PrivacyPolicyView()
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

                // Delete account
                Section {
                    Button(role: .destructive) {
                        showingDeleteAccount = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            } else {
                                Text("Delete Account")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text("Permanently deletes your account and everything you've saved.")
                }

                // App version
                Section {
                    HStack {
                        Spacer()
                        Text(SupportContact.appVersion)
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
            .alert("Delete your account?", isPresented: $showingDeleteAccount) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes your saves, quotes, notes, PDFs and screenshots. It can't be undone.")
            }
            .alert("Couldn't Delete Your Account", isPresented: .init(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing was lost. Check your connection and try again, or contact support.")
            }
            .confirmationDialog("Contact Support", isPresented: $showingContactOptions, titleVisibility: .visible) {
                Button("Email in Mail") { openSupportEmail(SupportContact.mailURL) }
                Button("Email in Gmail") { openSupportEmail(SupportContact.gmailURL) }
                Button("Copy Email Address") { copySupportAddress() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SupportContact.email)
            }
            .alert("Email Address Copied", isPresented: $showingCopiedAddress) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(SupportContact.email) is on your clipboard.")
            }
            .task {
                await viewModel.loadStats()
            }
        }
    }

    /// Opens the mail app; when it can't (Gmail not installed, Mail deleted), copies the address instead
    private func openSupportEmail(_ url: URL?) {
        guard let url else { return copySupportAddress() }
        UIApplication.shared.open(url) { opened in
            if !opened { copySupportAddress() }
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            defer { isDeletingAccount = false }
            do {
                try await authService.deleteAccount()
                HapticManager.saveSuccess()
            } catch {
                deleteAccountError = error
                HapticManager.error()
            }
        }
    }

    private func copySupportAddress() {
        UIPasteboard.general.string = SupportContact.email
        showingCopiedAddress = true
    }
}

// MARK: - Profile ViewModel

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var documentCount: Int = 0
    @Published var totalReadingMinutes: Int = 0
    @Published var documentsThisWeek: Int = 0
    /// Saves from the last 7 days, newest first
    @Published var weeklyDocuments: [Document] = []

    private let documentService = DocumentService.shared

    /// A name and how many saves carry it, for the category, topic and source lists
    struct Tally: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    struct SourceTally: Identifiable {
        let type: SourceType
        let count: Int
        var id: String { type.rawValue }
    }

    struct DaySaves: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    /// Start of the 7-day window: midnight six days ago, so "this week" is today plus the six days before
    static var weekStart: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    var formattedReadingTime: String { Self.format(minutes: totalReadingMinutes) }

    var weeklyReadingMinutes: Int {
        weeklyDocuments.compactMap { $0.readingTimeMinutes }.reduce(0, +)
    }

    var formattedWeeklyReadingTime: String { Self.format(minutes: weeklyReadingMinutes) }

    /// One entry per day of the window, oldest first, including days with no saves
    var savesPerDay: [DaySaves] {
        let calendar = Calendar.current
        let counts = Dictionary(grouping: weeklyDocuments) { calendar.startOfDay(for: $0.createdAt) }
            .mapValues(\.count)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: Self.weekStart)
        }
        .map { DaySaves(day: $0, count: counts[$0] ?? 0) }
    }

    /// The week's saves split by day, newest day first
    var weeklyDocumentsByDay: [(day: Date, documents: [Document])] {
        let calendar = Calendar.current
        return Dictionary(grouping: weeklyDocuments) { calendar.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, documents: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    var weeklyCategories: [Tally] { Self.tally(weeklyDocuments.flatMap(\.userCategories), limit: 5) }

    var weeklyTopics: [Tally] { Self.tally(weeklyDocuments.flatMap { $0.aiTopics ?? [] }, limit: 8) }

    var weeklySources: [SourceTally] {
        Dictionary(grouping: weeklyDocuments, by: \.sourceType)
            .map { SourceTally(type: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.type.displayName < $1.type.displayName }
    }

    func loadStats() async {
        let documents: [Document]
        if AuthService.shared.currentUser?.email == "demo@commonplace.app" {
            documents = documentService.fetchDemoDocuments()
        } else {
            do {
                documents = try await documentService.fetchCompletedDocuments()
            } catch {
                print("Failed to load stats: \(error)")
                return
            }
        }

        documentCount = documents.count
        totalReadingMinutes = documents.compactMap { $0.readingTimeMinutes }.reduce(0, +)
        let weekStart = Self.weekStart
        weeklyDocuments = documents
            .filter { $0.createdAt >= weekStart }
            .sorted { $0.createdAt > $1.createdAt }
        documentsThisWeek = weeklyDocuments.count
    }

    /// Most common first, ties alphabetical
    private static func tally(_ names: [String], limit: Int) -> [Tally] {
        Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
            .map { Tally(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }

    private static func format(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
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

struct CategoriesSettingsView: View {
    @ObservedObject private var categoryService = CategoryService.shared
    @State private var newCategoryName = ""
    @State private var showingAddCategory = false
    @State private var showingDuplicate = false

    private var builtIn: [Category] { categoryService.categories.filter(\.isSystem) }
    private var own: [Category] { categoryService.categories.filter { !$0.isSystem } }

    var body: some View {
        List {
            Section {
                if own.isEmpty {
                    Text("Categories you add appear here, in the Library filters and when you file a save.")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)
                } else {
                    ForEach(own) { category in
                        categoryRow(category)
                    }
                    .onDelete { offsets in
                        offsets.map { own[$0] }.forEach(categoryService.remove)
                    }
                }

                Button {
                    showingAddCategory = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.cpTint)
                        Text("Add Category")
                    }
                }
            } header: {
                Text("Your Categories")
            } footer: {
                if !own.isEmpty {
                    Text("Swipe left to remove one. Saves already filed under it keep the label.")
                }
            }

            Section {
                ForEach(builtIn) { category in
                    categoryRow(category)
                }
            } header: {
                Text("Built In")
            } footer: {
                Text("Sangrah files new saves under these automatically.")
            }
        }
        .navigationTitle("Categories")
        .task {
            await categoryService.load()
        }
        .alert("Add Category", isPresented: $showingAddCategory) {
            TextField("Category Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
            Button("Add") {
                let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                newCategoryName = ""
                if !name.isEmpty && !categoryService.add(named: name) {
                    showingDuplicate = true
                }
            }
        }
        .alert("Already a Category", isPresented: $showingDuplicate) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There's already a category with that name.")
        }
        .alert("Couldn't Save Categories", isPresented: .init(
            get: { categoryService.error != nil },
            set: { if !$0 { categoryService.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(categoryService.error?.localizedDescription ?? "Something went wrong.")
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack {
            Text(category.icon ?? "📁")
            Text(category.name)
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
    @ObservedObject private var savedQuotes = SavedQuoteService.shared

    /// Quotes bookmarked in the same 7-day window, newest first
    private var weeklyQuotes: [SavedQuote] {
        let start = ProfileViewModel.weekStart
        return savedQuotes.quotes.filter { $0.createdAt >= start }
    }

    var body: some View {
        List {
            Section {
                savesChart
                StatsRow(icon: "doc.text", title: "Saved", value: "\(viewModel.documentsThisWeek)")
                StatsRow(icon: "bookmark", title: "Quotes Bookmarked", value: "\(weeklyQuotes.count)")
                StatsRow(icon: "clock", title: "Est. Reading Time", value: viewModel.formattedWeeklyReadingTime)
            } header: {
                Text("Last 7 Days")
            } footer: {
                Text("Reading time is the estimated length of what you saved.")
            }

            if let latest = weeklyQuotes.first {
                Section("Latest Quote") {
                    VStack(alignment: .leading, spacing: CPSpacing.xs) {
                        Text("\u{201C}\(latest.shareable.displayText)\u{201D}")
                            .font(.cpCallout)
                            .italic()
                            .lineLimit(4)
                        if let title = latest.document?.title {
                            Text(title)
                                .font(.cpCaption1)
                                .foregroundColor(.cpTextSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, CPSpacing.xs)
                }
            }

            if !viewModel.weeklyCategories.isEmpty {
                Section("Top Categories") {
                    ForEach(viewModel.weeklyCategories) { category in
                        countRow(category.name, count: category.count)
                    }
                }
            }

            if !viewModel.weeklyTopics.isEmpty {
                Section("Top Topics") {
                    FlowLayout(spacing: CPSpacing.xs) {
                        ForEach(viewModel.weeklyTopics) { topic in
                            Text("\(topic.name) \u{00B7} \(topic.count)")
                                .font(.cpSubhead)
                                .foregroundColor(.cpTint)
                                .padding(.horizontal, CPSpacing.sm)
                                .padding(.vertical, CPSpacing.xxs)
                                .background(Color.cpTint.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.vertical, CPSpacing.xs)
                }
            }

            if !viewModel.weeklySources.isEmpty {
                Section("Sources") {
                    ForEach(viewModel.weeklySources) { source in
                        HStack(spacing: CPSpacing.sm) {
                            SourceIcon(type: source.type, size: 18)
                                .frame(width: 24)
                            Text(source.type.displayName)
                                .font(.cpBody)
                            Spacer()
                            Text("\(source.count)")
                                .font(.cpBody)
                                .foregroundColor(.cpTextSecondary)
                        }
                    }
                }
            }

            if viewModel.weeklyDocuments.isEmpty {
                Section("Saved This Week") {
                    Text("Nothing saved in the last 7 days")
                        .font(.cpBody)
                        .foregroundColor(.cpTextSecondary)
                }
            } else {
                ForEach(viewModel.weeklyDocumentsByDay, id: \.day) { group in
                    Section(Self.dayTitle(group.day)) {
                        ForEach(group.documents) { document in
                            // Same link style as the rest of Profile's stack: a value link
                            // here, under a destination link, bounces straight back
                            NavigationLink {
                                DocumentDetailView(document: document)
                            } label: {
                                savedRow(document)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Weekly Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadStats()
            await savedQuotes.load()
        }
    }

    /// Saves per day for the window, one bar per day with its count above it
    private var savesChart: some View {
        Chart(viewModel.savesPerDay) { day in
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Saves", day.count)
            )
            .foregroundStyle(Color.cpTint)
            .cornerRadius(4)
            .annotation(position: .top) {
                if day.count > 0 {
                    Text("\(day.count)")
                        .font(.cpCaption2)
                        .foregroundColor(.cpTextSecondary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 120)
        .padding(.vertical, CPSpacing.xs)
    }

    private func countRow(_ name: String, count: Int) -> some View {
        HStack {
            Text(name)
                .font(.cpBody)
            Spacer()
            Text("\(count)")
                .font(.cpBody)
                .foregroundColor(.cpTextSecondary)
        }
    }

    private func savedRow(_ document: Document) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.sm) {
            SourceIcon(type: document.sourceType, size: 16)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.cpBody)
                    .lineLimit(2)
                Text("\(document.sourceType.displayName) \u{00B7} \(document.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.cpCaption1)
                    .foregroundColor(.cpTextSecondary)
            }
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }
}
