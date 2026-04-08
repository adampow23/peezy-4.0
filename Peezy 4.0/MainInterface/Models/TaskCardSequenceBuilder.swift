import Foundation

// MARK: - Task Card Sequence Builder
// Converts a PeezyCard into a TaskCardSequence based on its type.
// Standalone struct — does not depend on view models.

struct TaskCardSequenceBuilder {

    static func build(
        task: PeezyCard,
        isSubscribed: Bool,
        completedTaskCount: Int,
        qualifying: WorkflowQualifying?,
        userState: UserState?
    ) -> TaskCardSequence {

        let taskId = task.taskId ?? task.id
        let category = task.taskCategory ?? "Task"
        let icon = task.icon

        // ── Paywall gate — only after user has completed 3+ tasks ──
        if !isSubscribed && completedTaskCount >= 3 {
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "Get Started", secondaryLabel: "Later"),
                    .paywall
                ],
                isPaywallGated: true,
                needsWorkflowContinue: false,
                showVerifiedBadge: false
            )
        }

        // ── Inventory (scanner triggered separately via fullScreenCover) ──
        if task.actionType == "in-app-inventory" {
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "Start Scan", secondaryLabel: "Later"),
                    infoCard(id: "\(taskId)-why", category: category, icon: icon,
                             title: "Why this matters", body: task.whyNeeded ?? task.subtitle),
                    summaryCard(id: "\(taskId)-done", category: category, icon: icon)
                ],
                isPaywallGated: false,
                needsWorkflowContinue: false,
                showVerifiedBadge: false
            )
        }

        // ── Self-service only (no Peezy/self choice) ──
        if task.selfServiceOnly {
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "On It", secondaryLabel: "Later"),
                    infoCard(id: "\(taskId)-info", category: category, icon: icon,
                             title: task.title, body: task.tips ?? task.whyNeeded ?? task.subtitle),
                    summaryCard(id: "\(taskId)-done", category: category, icon: icon)
                ],
                isPaywallGated: false,
                needsWorkflowContinue: false,
                showVerifiedBadge: false
            )
        }

        // ── Route by taskType ──
        switch task.taskType {

        case "provide_info":
            return buildProvideInfo(task: task, taskId: taskId, category: category, icon: icon)

        case "research":
            return buildResearch(task: task, taskId: taskId, category: category, icon: icon)

        case "transfer_cancel":
            return buildTransferCancel(task: task, taskId: taskId, category: category, icon: icon)

        case "survey":
            return buildSurvey(task: task, taskId: taskId, category: category, icon: icon,
                               qualifying: qualifying)

        default:
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "On It", secondaryLabel: "Later"),
                    infoCard(id: "\(taskId)-info", category: category, icon: icon,
                             title: task.title, body: task.whyNeeded ?? task.subtitle),
                    summaryCard(id: "\(taskId)-done", category: category, icon: icon)
                ],
                isPaywallGated: false,
                needsWorkflowContinue: false,
                showVerifiedBadge: false
            )
        }
    }

    // MARK: - Type-Specific Builders

    private static func buildProvideInfo(task: PeezyCard, taskId: String, category: String, icon: String) -> TaskCardSequence {
        TaskCardSequence(
            id: taskId,
            task: task,
            cards: [
                titleCard(task: task, category: category, icon: icon,
                          primaryLabel: "On It", secondaryLabel: "Later"),
                infoCard(id: "\(taskId)-info", category: category, icon: icon,
                         title: task.title, body: task.tips ?? task.whyNeeded ?? task.subtitle),
                summaryCard(id: "\(taskId)-done", category: category, icon: icon)
            ],
            isPaywallGated: false,
            needsWorkflowContinue: false,
            showVerifiedBadge: false
        )
    }

    private static func buildResearch(task: PeezyCard, taskId: String, category: String, icon: String) -> TaskCardSequence {
        // No title card — user already committed on home screen
        var cards: [TaskCardSpec] = [
            .tiles(TaskCardTilesData(
                cardId: "\(taskId)-choice",
                category: category,
                headerIcon: icon,
                title: "How would you like to handle this?",
                tiles: [
                    TileOption(id: "peezy", label: "Let Peezy handle it", icon: "hands.sparkles.fill",
                               subtitle: task.estPeezy),
                    TileOption(id: "self", label: "I'll do it myself", icon: "person.fill",
                               subtitle: formatEstHours(task.estHours))
                ],
                mode: .single,
                answerKey: "handleChoice"
            ))
        ]

        // Confirm card only if fields exist for this task
        let fields = ConfirmField.fields(for: taskId)
        if !fields.isEmpty {
            cards.append(.confirm(TaskCardConfirmData(
                cardId: "\(taskId)-confirm",
                category: category,
                headerIcon: icon,
                taskTitle: task.title,
                fields: fields
            )))
        }

        cards.append(summaryCard(id: "\(taskId)-done", category: category, icon: icon))

        return TaskCardSequence(
            id: taskId,
            task: task,
            cards: cards,
            isPaywallGated: false,
            needsWorkflowContinue: false,
            showVerifiedBadge: false
        )
    }

    private static func buildTransferCancel(task: PeezyCard, taskId: String, category: String, icon: String) -> TaskCardSequence {
        // No title card — user already committed on home screen
        var cards: [TaskCardSpec] = [
            .tiles(TaskCardTilesData(
                cardId: "\(taskId)-choice",
                category: category,
                headerIcon: icon,
                title: "What would you like to do?",
                tiles: [
                    TileOption(id: "update", label: "Update with current provider", icon: "arrow.triangle.2.circlepath",
                               subtitle: task.estPeezy),
                    TileOption(id: "cancel", label: "Cancel and find a new one", icon: "xmark.circle",
                               subtitle: formatEstHours(task.estHours))
                ],
                mode: .single,
                answerKey: "transferChoice"
            ))
        ]

        let fields = ConfirmField.fields(for: taskId)
        if !fields.isEmpty {
            cards.append(.confirm(TaskCardConfirmData(
                cardId: "\(taskId)-confirm",
                category: category,
                headerIcon: icon,
                taskTitle: task.title,
                fields: fields
            )))
        }

        cards.append(summaryCard(id: "\(taskId)-done", category: category, icon: icon))

        return TaskCardSequence(
            id: taskId,
            task: task,
            cards: cards,
            isPaywallGated: false,
            needsWorkflowContinue: false,
            showVerifiedBadge: false
        )
    }

    private static func buildSurvey(task: PeezyCard, taskId: String, category: String, icon: String, qualifying: WorkflowQualifying?) -> TaskCardSequence {
        // No title card — user already committed on home screen
        var cards: [TaskCardSpec] = []

        if let q = qualifying {
            // Add tile card per workflow question
            for (index, question) in q.questions.enumerated() {
                let tileOptions = question.options.map { opt in
                    TileOption(
                        id: opt.id,
                        label: opt.label,
                        icon: opt.icon,
                        subtitle: opt.subtitle,
                        isExclusive: opt.exclusive ?? false
                    )
                }

                // Determine if this question has a conditional skip
                let condition = conditionForQuestion(questionId: question.id)

                // Context-only cards (empty options) become info cards
                if question.options.isEmpty {
                    cards.append(infoCard(
                        id: "\(taskId)-q\(index)",
                        category: category,
                        icon: icon,
                        title: question.question,
                        body: question.subtitle ?? "",
                        showWhen: condition
                    ))
                } else {
                    cards.append(.tiles(TaskCardTilesData(
                        cardId: "\(taskId)-q\(index)",
                        category: category,
                        headerIcon: icon,
                        title: question.question,
                        body: question.subtitle,
                        tiles: tileOptions,
                        mode: question.type == .single_select ? .single : .multi,
                        answerKey: question.id,
                        workflowQuestionId: question.id,
                        showWhen: condition
                    )))
                }
            }
        }

        cards.append(summaryCard(id: "\(taskId)-done", category: category, icon: icon,
                                 title: "Here's what we've got",
                                 body: qualifying?.recap?.closing ?? "We'll reach out as soon as we have more information.",
                                 primaryLabel: qualifying?.recap?.button ?? "Request Quotes"))

        return TaskCardSequence(
            id: taskId,
            task: task,
            cards: cards,
            isPaywallGated: false,
            needsWorkflowContinue: qualifying != nil,
            showVerifiedBadge: true
        )
    }

    // MARK: - Conditional Skip Mapping
    // Maps question IDs to the conditions that must be met for them to show.
    // Add new conditions here as workflows evolve.

    private static func conditionForQuestion(questionId: String) -> CardCondition? {
        switch questionId {
        // Book Movers: storage details only shows if they said yes to storage
        case "storage_details":
            return CardCondition(answerKey: "storage_needed", requiredValues: ["yes"])

        // Book Cleaners: move-out timing only shows if they picked move_out or both
        case "move_out_timing":
            return CardCondition(answerKey: "which_place", requiredValues: ["move_out", "both"])

        // Book Cleaners: move-in timing only shows if they picked move_in or both
        case "move_in_timing":
            return CardCondition(answerKey: "which_place", requiredValues: ["move_in", "both"])

        // Internet/Utilities: current provider card only shows if user chose help_me
        case "current_provider":
            return CardCondition(answerKey: "help_preference", requiredValues: ["help_me"])

        default:
            return nil
        }
    }

    // MARK: - Card Factories

    private static func titleCard(task: PeezyCard, category: String, icon: String, primaryLabel: String, secondaryLabel: String?) -> TaskCardSpec {
        .title(TaskCardTitleData(
            cardId: "\(task.taskId ?? task.id)-title",
            category: category,
            headerIcon: icon,
            title: task.title,
            body: task.subtitle,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel
        ))
    }

    private static func infoCard(id: String, category: String, icon: String, title: String, body: String, showWhen: CardCondition? = nil) -> TaskCardSpec {
        .info(TaskCardInfoData(
            cardId: id,
            category: category,
            headerIcon: icon,
            title: title,
            body: body,
            primaryLabel: "Continue",
            showWhen: showWhen
        ))
    }

    private static func summaryCard(id: String, category: String, icon: String,
                                     title: String = "You're all set!",
                                     body: String = "We'll take it from here. You can check on this task anytime in the Tasks tab.",
                                     primaryLabel: String = "Done") -> TaskCardSpec {
        .summary(TaskCardSummaryData(
            cardId: id,
            category: category,
            headerIcon: icon,
            title: title,
            body: body,
            primaryLabel: primaryLabel
        ))
    }

    // MARK: - Helpers

    static func formatEstHours(_ hours: Double?) -> String? {
        guard let hours = hours, hours > 0 else { return nil }
        if hours < 1 {
            let minutes = Int(hours * 60)
            return "Usually \(minutes) min"
        } else if hours == 1 {
            return "Usually ~1 hour"
        } else {
            let low = Int(hours)
            let high = low + 1
            return "Usually \(low)-\(high) hours"
        }
    }
}
