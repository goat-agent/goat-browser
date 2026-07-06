import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 22)
            ProfileSwitcher(model: model)
                .padding(.horizontal, DS.Space.sm)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.ungroupedTabs) { tab in
                        TabRow(model: model, tab: tab,
                               isActive: tab.id == model.activeTabId,
                               indented: false,
                               onSelect: { model.activate(id: tab.id) },
                               onClose: { model.closeTab(id: tab.id) })
                    }
                    ForEach(model.groups) { group in
                        GroupBlock(model: model, group: group)
                    }
                    GhostNewTabRow { model.openCommandBarForNewTab() }
                }
                .padding(DS.Space.sm)
            }
        }
    }
}

private struct ProfileSwitcher: View {
    @Bindable var model: BrowserViewModel
    @State private var hovering = false
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: DS.Space.sm) {
                ProfileAvatar(profile: model.activeProfile)
                Text(model.activeProfile.name)
                    .font(DS.Fonts.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .padding(.horizontal, DS.Space.sm + 2)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(hovering ? DS.Colors.fillHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(model.profiles) { profile in
                    Button {
                        model.switchProfile(to: profile.id)
                        showing = false
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            ProfileAvatar(profile: profile)
                            Text(profile.name).font(DS.Fonts.body)
                                .foregroundStyle(DS.Colors.textPrimary)
                            Spacer(minLength: 12)
                            if profile.id == model.activeProfileId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.vertical, 4)
                MenuTextButton(title: "New Profile…") {}
                MenuTextButton(title: "Manage Profiles…") {}
            }
            .padding(DS.Space.sm)
            .frame(width: 232)
        }
    }
}

private struct MenuTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.textPrimary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileAvatar: View {
    let profile: Profile

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.favicon + 1, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [DS.Colors.groupPalette[profile.colorIndex % DS.Colors.groupPalette.count],
                             DS.Colors.groupPalette[profile.colorIndex % DS.Colors.groupPalette.count].opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 20, height: 20)
            .overlay(
                Text(profile.avatarInitial)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

private struct GroupBlock: View {
    @Bindable var model: BrowserViewModel
    @Bindable var group: TabGroup

    private var color: Color {
        DS.Colors.groupPalette[group.colorIndex % DS.Colors.groupPalette.count]
    }

    var body: some View {
        let members = model.tabs(in: group)
        VStack(alignment: .leading, spacing: 2) {
            Button {
                model.toggleGroupCollapsed(group)
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(width: 10)
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(group.displayName)
                        .font(DS.Fonts.tabLabel.weight(.semibold))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(members.count)")
                        .font(DS.Fonts.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DS.Colors.fillSubtle))
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !group.isCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(members) { tab in
                        TabRow(model: model, tab: tab,
                               isActive: tab.id == model.activeTabId,
                               indented: true,
                               onSelect: { model.activate(id: tab.id) },
                               onClose: { model.closeTab(id: tab.id) })
                    }
                }
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    Rectangle().fill(color.opacity(0.5)).frame(width: 2)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct TabRow: View {
    var model: BrowserViewModel
    @Bindable var tab: Tab
    let isActive: Bool
    let indented: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            favicon.frame(width: DS.Metrics.faviconSize, height: DS.Metrics.faviconSize)
            Text(tab.displayLabel)
                .lineLimit(1).truncationMode(.tail)
                .font(DS.Fonts.tabLabel)
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer(minLength: 0)
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            } else if tab.isLoading {
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DS.Space.sm)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Duplicate Tab") { model.duplicateTab(id: tab.id) }
            if tab.groupId == nil {
                Button("New Group with Tab") { model.groupTab(tab.id) }
            } else {
                Button("Remove from Group") { model.ungroupTab(tab.id) }
            }
            Divider()
            Button("Close Tab") { model.closeTab(id: tab.id) }
            Button("Close Other Tabs") { model.closeOtherTabs(exceptId: tab.id) }
            Button("Close Tabs to the Right") { model.closeTabsToRight(ofId: tab.id) }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        if isActive {
            shape.fill(DS.Colors.fillActive)
                .overlay(shape.strokeBorder(DS.Colors.glassStroke, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        } else if hovering {
            shape.fill(DS.Colors.fillHover)
        } else {
            shape.fill(.clear)
        }
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.faviconPNG, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }
}

private struct GhostNewTabRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: DS.Metrics.faviconSize, height: DS.Metrics.faviconSize)
                Text("New Tab").font(DS.Fonts.tabLabel)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DS.Colors.textSecondary)
            .padding(.vertical, 6)
            .padding(.horizontal, DS.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(hovering ? DS.Colors.fillHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.top, 2)
    }
}
