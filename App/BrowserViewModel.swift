import Foundation
import AppKit
import Observation

// BrowserViewModel — the main-actor owner of the tab list, the active tab, and
// the GoatCEF engine. It conforms to GoatCEFDelegate (an ObjC protocol) to
// receive bridge callbacks; the bridge guarantees these arrive on the main
// thread, so we assume main-actor isolation inside them.
//
// It is an NSObject subclass so it can be passed to the ObjC bridge as a
// delegate. @Observable drives SwiftUI updates.
@MainActor
@Observable
final class BrowserViewModel: NSObject, GoatCEFDelegate {
    var tabs: [Tab] = []
    var activeTabId: Int?

    // Command bar state (presentation owned by the view, content by the model).
    var commandBarVisible = false
    var commandBarText = ""
    // When true, the command bar opens a brand-new tab on submit instead of
    // navigating the active tab.
    var commandBarForNewTab = false
    var commandSuggestions: [Suggestion] = []
    var selectedSuggestionIndex = 0

    // Sidebar collapse state (Cmd+\).
    var sidebarVisible = true

    // Downloads tracking + downloads popover visibility (sidebar-bottom button).
    let downloads = DownloadsModel()
    var downloadsPopoverVisible = false

    // Find-in-page (Cmd+F) state; the bar renders in the overlay panel.
    let find = FindModel()

    // Pending permission request shown in the overlay panel (one at a time).
    var pendingPermission: PermissionRequest?

    private(set) var profiles: [Profile]
    var activeProfileId: UUID
    var groups: [TabGroup] = []

    private var nextTabId = 1
    private let newTabURL = "goat://newtab"

    override init() {
        if let loaded = ProfileStore.load() {
            profiles = loaded.profiles
            activeProfileId = loaded.activeId
        } else {
            let personal = Profile(name: "Personal", colorIndex: 1)
            profiles = [personal]
            activeProfileId = personal.id
        }
        super.init()
        ProfileStore.save(profiles: profiles, activeId: activeProfileId)
    }

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileId } ?? profiles[0]
    }

    func switchProfile(to id: UUID) {
        guard id != activeProfileId, profiles.contains(where: { $0.id == id }) else { return }
        saveSessionNow()
        for tab in tabs { engine?.closeTab(tab.id) }
        tabs.removeAll()
        groups.removeAll()
        activeTabId = nil
        activeProfileId = id
        ProfileStore.save(profiles: profiles, activeId: id)
        restoreActiveProfileSession()
    }

    @discardableResult
    func addProfile(name: String) -> Profile {
        let used = Set(profiles.map { $0.colorIndex })
        let colorIndex = (0..<DS.Colors.groupPalette.count).first { !used.contains($0) } ?? 0
        let profile = Profile(name: name, colorIndex: colorIndex)
        profiles.append(profile)
        ProfileStore.save(profiles: profiles, activeId: activeProfileId)
        switchProfile(to: profile.id)
        return profile
    }

    var ungroupedTabs: [Tab] {
        tabs.filter { $0.groupId == nil }
    }

    func tabs(in group: TabGroup) -> [Tab] {
        tabs.filter { $0.groupId == group.id }
    }

    func group(for tab: Tab) -> TabGroup? {
        guard let gid = tab.groupId else { return nil }
        return groups.first { $0.id == gid }
    }

    @discardableResult
    func makeGroup(with tabIds: [Int]) -> TabGroup {
        let used = Set(groups.map { $0.colorIndex })
        let colorIndex = (0..<DS.Colors.groupPalette.count).first { !used.contains($0) } ?? 0
        let group = TabGroup(colorIndex: colorIndex)
        groups.append(group)
        for id in tabIds {
            tabs.first { $0.id == id }?.groupId = group.id
        }
        scheduleSessionSave()
        return group
    }

    func toggleGroupCollapsed(_ group: TabGroup) {
        group.isCollapsed.toggle()
        scheduleSessionSave()
    }

    // The engine is created lazily once the container view exists.
    @ObservationIgnored private(set) var engine: GoatCEF?

    var activeTab: Tab? {
        guard let id = activeTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    // MARK: - Engine lifecycle

    func attachEngine(container: NSView) {
        guard engine == nil else { return }
        engine = GoatCEF(container: container, delegate: self)
    }

    func openInitialTabIfNeeded(url: String) {
        guard tabs.isEmpty else {
            retryPendingCreations()
            return
        }
        guard !didBootstrap else { return }
        didBootstrap = true
        restoreActiveProfileSession()
    }

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var sessionSaveWork: DispatchWorkItem?

    @ObservationIgnored private static var didGlobalBootstrap = false

    private func restoreActiveProfileSession() {
        guard !BrowserViewModel.didGlobalBootstrap else {
            newTab(url: newTabURL)
            return
        }
        BrowserViewModel.didGlobalBootstrap = true
        if let snapshot = SessionStore.load(),
           let session = snapshot.profiles.first(where: { $0.profileId == activeProfileId.uuidString }),
           !session.tabs.isEmpty {
            restore(session)
        } else {
            newTab(url: newTabURL)
        }
    }

    private func restore(_ session: ProfileSession) {
        groups = session.groups.map { gs in
            let group = TabGroup(id: UUID(uuidString: gs.id) ?? UUID(), name: gs.name, colorIndex: gs.colorIndex)
            group.isCollapsed = gs.isCollapsed
            return group
        }
        var maxId = nextTabId - 1
        for ts in session.tabs {
            let tab = Tab(id: ts.id, urlString: ts.url, title: ts.title)
            tab.groupId = ts.groupId.flatMap { UUID(uuidString: $0) }
            tabs.append(tab)
            maxId = max(maxId, ts.id)
            engine?.createTab(withId: ts.id, url: ts.url)
        }
        nextTabId = maxId + 1
        if let active = session.activeTabId ?? session.tabs.first?.id {
            activeTabId = active
            engine?.activateTab(active)
        }
        if !GoatCEF.isInitialized() { scheduleRetry() }
    }

    func scheduleSessionSave() {
        sessionSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSessionNow() }
        sessionSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveSessionNow() {
        var snapshot = SessionStore.load()
            ?? SessionSnapshot(savedAt: 0, activeProfileId: activeProfileId.uuidString, profiles: [])
        snapshot.savedAt = Date().timeIntervalSince1970
        snapshot.activeProfileId = activeProfileId.uuidString
        let session = ProfileSession(
            profileId: activeProfileId.uuidString,
            activeTabId: activeTabId,
            tabs: tabs.map {
                TabSession(id: $0.id, url: $0.urlString, title: $0.title, groupId: $0.groupId?.uuidString)
            },
            groups: groups.map {
                GroupSession(id: $0.id.uuidString, name: $0.name, colorIndex: $0.colorIndex, isCollapsed: $0.isCollapsed)
            })
        snapshot.profiles.removeAll { $0.profileId == activeProfileId.uuidString }
        snapshot.profiles.append(session)
        SessionStore.save(snapshot)
    }

    // Re-issue createTab for any tab the engine hasn't created yet. The bridge
    // is idempotent (dedupes by map + in-flight queue), so this is safe to call
    // repeatedly from layout passes. Used to recover from CEF not being ready on
    // the first attempt.
    @ObservationIgnored private var didScheduleRetry = false

    private func retryPendingCreations() {
        guard let engine else { return }
        guard GoatCEF.isInitialized() else {
            scheduleRetry()
            return
        }
        for tab in tabs {
            engine.createTab(withId: tab.id, url: tab.urlString)
        }
        if let id = activeTabId {
            engine.activateTab(id)
        }
    }

    private func scheduleRetry() {
        guard !didScheduleRetry else { return }
        didScheduleRetry = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.didScheduleRetry = false
            self.retryPendingCreations()
        }
    }

    // MARK: - Tab operations

    @discardableResult
    func newTab(url: String) -> Tab {
        let id = nextTabId
        nextTabId += 1
        let tab = Tab(id: id, urlString: url)
        tabs.append(tab)
        // Set active BEFORE asking the engine to create, so onBrowserCreated can
        // show it immediately when it becomes the active tab.
        activeTabId = id
        engine?.createTab(withId: id, url: url)
        if !GoatCEF.isInitialized() {
            scheduleRetry()
        }
        scheduleSessionSave()
        return tab
    }

    func closeTab(id: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        if closing.urlString != "goat://newtab", !closing.urlString.isEmpty {
            closedTabStack.append(closing.urlString)
        }
        engine?.closeTab(id)
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                activate(id: tabs[newIndex].id)
            }
        }
        scheduleSessionSave()
    }

    func activate(id: Int) {
        activeTabId = id
        engine?.activateTab(id)
        scheduleSessionSave()
    }

    func closeActiveTab() {
        guard let id = activeTabId else { return }
        closeTab(id: id)
    }

    @ObservationIgnored private var closedTabStack: [String] = []

    func duplicateTab(id: Int) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        newTab(url: tab.urlString)
    }

    func closeOtherTabs(exceptId id: Int) {
        for tabId in tabs.filter({ $0.id != id }).map({ $0.id }) {
            closeTab(id: tabId)
        }
    }

    func closeTabsToRight(ofId id: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        for tabId in tabs[(index + 1)...].map({ $0.id }) {
            closeTab(id: tabId)
        }
    }

    func reopenLastClosedTab() {
        guard let url = closedTabStack.popLast() else { return }
        newTab(url: url)
    }

    func selectNextTab() {
        guard let id = activeTabId,
              let index = tabs.firstIndex(where: { $0.id == id }), !tabs.isEmpty else { return }
        activate(id: tabs[(index + 1) % tabs.count].id)
    }

    func selectPreviousTab() {
        guard let id = activeTabId,
              let index = tabs.firstIndex(where: { $0.id == id }), !tabs.isEmpty else { return }
        activate(id: tabs[(index - 1 + tabs.count) % tabs.count].id)
    }

    func activateTab(index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activate(id: tabs[index].id)
    }

    func groupTab(_ id: Int) {
        makeGroup(with: [id])
    }

    func ungroupTab(_ id: Int) {
        tabs.first { $0.id == id }?.groupId = nil
        scheduleSessionSave()
    }

    func bookmarkCurrentTab() {
        guard let tab = activeTab,
              let scheme = URL(string: tab.urlString)?.scheme,
              scheme == "http" || scheme == "https" else { return }
        BookmarkStore.add(profileId: activeProfileId, url: tab.urlString, title: tab.title)
    }

    // MARK: - Navigation

    // Resolve `input` and navigate the given tab (or open a new tab).
    func navigate(tabId: Int, input: String) {
        guard let url = URLInputResolver.resolve(input) else { return }
        if let tab = tabs.first(where: { $0.id == tabId }) {
            tab.urlString = url.absoluteString
        }
        engine?.loadURL(url.absoluteString, inTab: tabId)
    }

    func navigateActive(input: String) {
        if let id = activeTabId {
            navigate(tabId: id, input: input)
        } else {
            openNewTab(input: input)
        }
    }

    func openNewTab(input: String) {
        guard let url = URLInputResolver.resolve(input) else { return }
        newTab(url: url.absoluteString)
    }

    func goBack() {
        guard let id = activeTabId else { return }
        engine?.goBack(id)
    }

    func goForward() {
        guard let id = activeTabId else { return }
        engine?.goForward(id)
    }

    func reload() {
        guard let id = activeTabId else { return }
        engine?.reload(id)
    }

    func stop() {
        guard let id = activeTabId else { return }
        engine?.stopLoad(id)
    }

    func showDevTools() {
        guard let id = activeTabId else { return }
        engine?.showDevTools(id)
    }

    // MARK: - Find-in-page

    func openFind() {
        find.visible = true
        // If there is an existing query, re-run it so the count refreshes.
        if !find.query.isEmpty, let id = activeTabId {
            engine?.find(find.query, tab: id, forward: true)
        }
    }

    func updateFindQuery(_ text: String) {
        find.query = text
        guard let id = activeTabId else { return }
        if text.isEmpty {
            engine?.stopFind(id, clearSelection: true)
            find.reset()
        } else {
            engine?.find(text, tab: id, forward: true)
        }
    }

    func findNext() {
        guard let id = activeTabId, !find.query.isEmpty else { return }
        engine?.find(find.query, tab: id, forward: true)
    }

    func findPrev() {
        guard let id = activeTabId, !find.query.isEmpty else { return }
        engine?.find(find.query, tab: id, forward: false)
    }

    func closeFind() {
        find.visible = false
        find.reset()
        if let id = activeTabId {
            engine?.stopFind(id, clearSelection: true)
        }
    }

    // MARK: - Zoom (CEF zoom level is logarithmic; +/- by 0.5 steps)

    private let zoomStep = 0.5

    func zoomIn() {
        guard let id = activeTabId, let engine else { return }
        let level = engine.zoom(id) + zoomStep
        engine.setZoom(level, tab: id)
        persistZoom(level)
    }

    func zoomOut() {
        guard let id = activeTabId, let engine else { return }
        let level = engine.zoom(id) - zoomStep
        engine.setZoom(level, tab: id)
        persistZoom(level)
    }

    func zoomReset() {
        guard let id = activeTabId else { return }
        engine?.setZoom(0, tab: id)
        persistZoom(0)
    }

    private func persistZoom(_ level: Double) {
        guard let host = activeTab.flatMap({ URL(string: $0.urlString)?.host }) else { return }
        ZoomPreferences.set(zoom: level, forHost: host)
    }

    // MARK: - Permissions

    // Decide a pending request, persist the choice, and answer the bridge.
    func resolvePermission(_ request: PermissionRequest, granted: Bool) {
        PermissionStore.store(origin: request.origin, kind: request.kind,
                              decision: granted ? .allow : .deny)
        engine?.respond(toPermission: request.id, granted: granted)
        if pendingPermission?.id == request.id {
            pendingPermission = nil
        }
    }

    // MARK: - Downloads

    func toggleDownloadsPopover() {
        downloadsPopoverVisible.toggle()
    }

    // MARK: - Command bar

    func openCommandBarForActiveTab() {
        commandBarForNewTab = false
        commandBarText = activeTab?.urlString ?? ""
        commandSuggestions = []
        selectedSuggestionIndex = 0
        commandBarVisible = true
    }

    func openCommandBarForNewTab() {
        commandBarForNewTab = true
        commandBarText = ""
        commandSuggestions = []
        selectedSuggestionIndex = 0
        commandBarVisible = true
    }

    func refreshSuggestions() {
        commandSuggestions = SuggestionEngine.suggestions(
            query: commandBarText, profileId: activeProfileId, openTabs: tabs)
        selectedSuggestionIndex = 0
    }

    func moveSuggestionSelection(_ delta: Int) {
        guard !commandSuggestions.isEmpty else { return }
        let count = commandSuggestions.count
        selectedSuggestionIndex = (selectedSuggestionIndex + delta % count + count) % count
    }

    func submitCommandBar() {
        if selectedSuggestionIndex < commandSuggestions.count,
           !commandBarText.isEmpty {
            let suggestion = commandSuggestions[selectedSuggestionIndex]
            activate(suggestion)
            return
        }
        let text = commandBarText
        let forNewTab = commandBarForNewTab
        dismissCommandBar()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if forNewTab {
            openNewTab(input: text)
        } else {
            navigateActive(input: text)
        }
    }

    func activate(_ suggestion: Suggestion) {
        let forNewTab = commandBarForNewTab
        dismissCommandBar()
        switch suggestion.kind {
        case let .openTab(tabId):
            activate(id: tabId)
        case .history, .bookmark:
            if forNewTab { newTab(url: suggestion.target) } else { navigateActive(input: suggestion.target) }
        case .search:
            if forNewTab { openNewTab(input: suggestion.target) } else { navigateActive(input: suggestion.target) }
        }
    }

    func dismissCommandBar() {
        commandBarVisible = false
        commandSuggestions = []
        selectedSuggestionIndex = 0
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    // MARK: - GoatCEFDelegate (main-thread callbacks from the bridge)

    nonisolated func tab(_ tabId: Int, didChangeURL url: String) {
        MainActor.assumeIsolated {
            guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
            tab.urlString = url
            HistoryStore.record(profileId: activeProfileId, url: url, title: tab.title)
            if let host = URL(string: url)?.host, let level = ZoomPreferences.zoom(forHost: host) {
                engine?.setZoom(level, tab: tabId)
            }
            scheduleSessionSave()
        }
    }

    nonisolated func tab(_ tabId: Int, didChangeTitle title: String) {
        MainActor.assumeIsolated {
            guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
            tab.title = title
            HistoryStore.updateTitle(profileId: activeProfileId, url: tab.urlString, title: title)
        }
    }

    nonisolated func tab(_ tabId: Int,
                         didChangeLoading isLoading: Bool,
                         canGoBack: Bool,
                         canGoForward: Bool) {
        MainActor.assumeIsolated {
            guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
            tab.isLoading = isLoading
            tab.canGoBack = canGoBack
            tab.canGoForward = canGoForward
        }
    }

    nonisolated func tab(_ tabId: Int, didChangeFavicon pngData: Data?) {
        MainActor.assumeIsolated {
            tabs.first { $0.id == tabId }?.faviconPNG = pngData
        }
    }

    nonisolated func tabDidRequestNewTab(withURL url: String) {
        MainActor.assumeIsolated {
            newTab(url: url)
        }
    }

    nonisolated func tab(_ tabId: Int,
                         requestPermission kind: String,
                         origin: String,
                         requestId reqId: Int) {
        MainActor.assumeIsolated {
            // If we already have a stored decision for this (origin, kind),
            // answer immediately without prompting. NEVER auto-grant unknowns.
            if let decided = PermissionStore.decision(origin: origin, kind: kind) {
                engine?.respond(toPermission: reqId, granted: decided == .allow)
                return
            }
            // Otherwise surface a prompt in the overlay panel. If one is already
            // showing, deny the new one to avoid a queue (sites can re-request).
            if pendingPermission != nil {
                engine?.respond(toPermission: reqId, granted: false)
                return
            }
            pendingPermission = PermissionRequest(id: reqId, tabId: tabId,
                                                  kind: kind, origin: origin)
        }
    }

    nonisolated func downloadDidUpdateId(_ downloadId: Int,
                                         fileName name: String,
                                         receivedBytes r: Int64,
                                         totalBytes t: Int64,
                                         complete done: Bool,
                                         path fullPath: String) {
        MainActor.assumeIsolated {
            downloads.update(id: downloadId, fileName: name, received: r,
                             total: t, complete: done, path: fullPath)
            // Auto-reveal the downloads popover when a download begins.
            if !done && !downloadsPopoverVisible {
                downloadsPopoverVisible = true
            }
        }
    }

    nonisolated func tab(_ tabId: Int,
                         didUpdateFindMatches current: Int,
                         of total: Int) {
        MainActor.assumeIsolated {
            guard tabId == activeTabId else { return }
            find.currentMatch = current
            find.totalMatches = total
        }
    }

    nonisolated func tab(_ tabId: Int, didChangeLoadProgress progress: Double) {
        MainActor.assumeIsolated {
            tabs.first { $0.id == tabId }?.loadProgress = progress
        }
    }
}
