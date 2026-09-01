import SwiftUI

enum TaskRowButtonStyle {
    case primary
    case secondary
    case destructiveLink
}

struct TaskRowButtonConfig: Identifiable {
    let id = UUID()
    let title: String
    let style: TaskRowButtonStyle
    let action: TaskAction
    let accessibilityIdentifier: String?

    init(
        title: String,
        style: TaskRowButtonStyle,
        action: TaskAction,
        accessibilityIdentifier: String? = nil
    ) {
        self.title = title
        self.style = style
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

enum TaskRowButtonLayout {
    case none
    case single(TaskRowButtonConfig)
    case singleWithLink(TaskRowButtonConfig, TaskRowButtonConfig)
    case pair(TaskRowButtonConfig, TaskRowButtonConfig)
    case pairWithLink(TaskRowButtonConfig, TaskRowButtonConfig, TaskRowButtonConfig)
}

struct TaskRowButtons: View {
    let layout: TaskRowButtonLayout
    let onAction: (TaskAction) -> Void

    var body: some View {
        switch layout {
        case .none:
            EmptyView()
        case .single(let btn):
            renderButton(btn)
        case .singleWithLink(let button, let link):
            VStack(spacing: 12) {
                renderButton(button)
                renderButton(link)
            }
        case .pair(let a, let b):
            HStack(spacing: 12) {
                renderButton(a).frame(maxWidth: .infinity)
                renderButton(b).frame(maxWidth: .infinity)
            }
        case .pairWithLink(let a, let b, let link):
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    renderButton(a).frame(maxWidth: .infinity)
                    renderButton(b).frame(maxWidth: .infinity)
                }
                renderButton(link)
            }
        }
    }

    @ViewBuilder
    private func renderButton(_ cfg: TaskRowButtonConfig) -> some View {
        if let identifier = cfg.accessibilityIdentifier {
            buttonContent(cfg)
                .accessibilityIdentifier(identifier)
        } else {
            buttonContent(cfg)
        }
    }

    @ViewBuilder
    private func buttonContent(_ cfg: TaskRowButtonConfig) -> some View {
        switch cfg.style {
        case .primary:
            PeezyAssessmentButton(cfg.title) {
                onAction(cfg.action)
            }
        case .secondary:
            SecondaryActionButton(title: cfg.title) {
                onAction(cfg.action)
            }
        case .destructiveLink:
            Button {
                onAction(cfg.action)
            } label: {
                Text(cfg.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed.opacity(0.8))
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Layout resolver

    static func layout(for task: PeezyCard, section: TaskSection) -> TaskRowButtonLayout {
        guard task.dispositionContract == nil else { return .none }
        switch (section, task.status, task.isScanInventory) {
        case (.todo, _, _):
            return .single(.init(title: "Open Task", style: .primary, action: .open(task)))

        case (.userInProgress, .userInProgress, true):
            return .pairWithLink(
                .init(title: "Open Task", style: .secondary, action: .open(task)),
                .init(title: "Mark as complete", style: .primary, action: .markComplete(task)),
                .init(title: "Reset inventory", style: .destructiveLink, action: .resetInventory(task))
            )
        case (.userInProgress, .userInProgress, false):
            return .pair(
                .init(title: "Open Task", style: .secondary, action: .open(task)),
                .init(title: "Mark as complete", style: .primary, action: .markComplete(task))
            )

        case (.peezyOnIt, _, _):
            return .single(.init(title: "Open Task", style: .primary, action: .open(task)))

        case (.done, .completed, true):
            return .singleWithLink(
                .init(
                    title: "View inventory",
                    style: .primary,
                    action: .open(task),
                    accessibilityIdentifier: "viewInventoryButton"
                ),
                .init(title: "Reset inventory", style: .destructiveLink, action: .resetInventory(task))
            )
        case (.done, .completed, false):
            return .single(.init(title: "Undo", style: .primary, action: .undo(task)))

        default:
            return .none
        }
    }
}
