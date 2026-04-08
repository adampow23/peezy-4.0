import Foundation

// MARK: - Task Card Sequence Builder
// Converts a PeezyCard into a TaskCardSequence based on its type.
// Standalone struct — does not depend on view models.

struct TaskCardSequenceBuilder {

    static func build(
        task: PeezyCard,
        isSubscribed: Bool,
        qualifying: WorkflowQualifying?,
        userState: UserState?
    ) -> TaskCardSequence {

        let taskId = task.taskId ?? task.id
        let category = task.taskCategory ?? "Task"
        let icon = task.icon

        // ── Paywall gate ──
        if !isSubscribed {
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "Get Started", secondaryLabel: "Later"),
                    .paywall
                ],
                isPaywallGated: true,
                needsWorkflowContinue: false
            )
        }

        // ── Inventory (scanner triggered separately) ──
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
                needsWorkflowContinue: false
            )
        }

        // ── Self-service only (no Peezy/self choice) ──
        if task.selfServiceOnly {
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "Got It", secondaryLabel: "Later"),
                    infoCard(id: "\(taskId)-why", category: category, icon: icon,
                             title: "Why this matters", body: task.whyNeeded ?? task.subtitle),
                    infoCard(id: "\(taskId)-tips", category: category, icon: icon,
                             title: "Tips", body: task.tips ?? "Complete this task at your convenience."),
                    summaryCard(id: "\(taskId)-done", category: category, icon: icon)
                ],
                isPaywallGated: false,
                needsWorkflowContinue: false
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
            // Fallback — simple info sequence
            return TaskCardSequence(
                id: taskId,
                task: task,
                cards: [
                    titleCard(task: task, category: category, icon: icon,
                              primaryLabel: "Got It", secondaryLabel: "Later"),
                    infoCard(id: "\(taskId)-why", category: category, icon: icon,
                             title: "Why this matters", body: task.whyNeeded ?? task.subtitle),
                    summaryCard(id: "\(taskId)-done", category: category, icon: icon)
                ],
                isPaywallGated: false,
                needsWorkflowContinue: false
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
                          primaryLabel: "Learn More", secondaryLabel: "Later"),
                infoCard(id: "\(taskId)-why", category: category, icon: icon,
                         title: "Why this matters", body: task.whyNeeded ?? task.subtitle),
                infoCard(id: "\(taskId)-tips", category: category, icon: icon,
                         title: "What to do", body: task.tips ?? "Follow the guidance below."),
                summaryCard(id: "\(taskId)-done", category: category, icon: icon)
            ],
            isPaywallGated: false,
            needsWorkflowContinue: false
        )
    }

    private static func buildResearch(task: PeezyCard, taskId: String, category: String, icon: String) -> TaskCardSequence {
        var cards: [TaskCardSpec] = [
            titleCard(task: task, category: category, icon: icon,
                      primaryLabel: "Let's Go", secondaryLabel: "Later"),
            infoCard(id: "\(taskId)-why", category: category, icon: icon,
                     title: "Why this matters", body: task.whyNeeded ?? task.subtitle),
            .tiles(TaskCardTilesData(
                cardId: "\(taskId)-choice",
                category: category,
                headerIcon: icon,
                title: "How would you like to handle this?",
                body: nil,
                tiles: [
                    TileOption(id: "peezy", label: "Let Peezy handle it", icon: "hands.sparkles.fill"),
                    TileOption(id: "self", label: "I'll do it myself", icon: "person.fill")
                ],
                mode: .single,
                answerKey: "handleChoice",
                workflowQuestionId: nil
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
            needsWorkflowContinue: false
        )
    }

    private static func buildTransferCancel(task: PeezyCard, taskId: String, category: String, icon: String) -> TaskCardSequence {
        var cards: [TaskCardSpec] = [
            titleCard(task: task, category: category, icon: icon,
                      primaryLabel: "Let's Go", secondaryLabel: "Later"),
            infoCard(id: "\(taskId)-why", category: category, icon: icon,
                     title: "Why this matters", body: task.whyNeeded ?? task.subtitle),
            .tiles(TaskCardTilesData(
                cardId: "\(taskId)-choice",
                category: category,
                headerIcon: icon,
                title: "What would you like to do?",
                body: nil,
                tiles: [
                    TileOption(id: "update", label: "Update with current provider", icon: "arrow.triangle.2.circlepath"),
                    TileOption(id: "cancel", label: "Cancel and find a new one", icon: "xmark.circle")
                ],
                mode: .single,
                answerKey: "transferChoice",
                workflowQuestionId: nil
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
            needsWorkflowContinue: false
        )
    }

    private static func buildSurvey(task: PeezyCard, taskId: String, category: String, icon: String, qualifying: WorkflowQualifying?) -> TaskCardSequence {
        var cards: [TaskCardSpec] = [
            titleCard(task: task, category: category, icon: icon,
                      primaryLabel: "Let's Go", secondaryLabel: "Later")
        ]

        // Add intro info from qualifying data
        if let q = qualifying {
            cards.append(infoCard(
                id: "\(taskId)-intro",
                category: category,
                icon: icon,
                title: q.intro.title,
                body: q.intro.subtitle ?? task.subtitle
            ))

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

                cards.append(.tiles(TaskCardTilesData(
                    cardId: "\(taskId)-q\(index)",
                    category: category,
                    headerIcon: icon,
                    title: question.question,
                    body: question.subtitle,
                    tiles: tileOptions,
                    mode: question.type == .single_select ? .single : .multi,
                    answerKey: question.id,
                    workflowQuestionId: question.id
                )))
            }
        }

        cards.append(summaryCard(id: "\(taskId)-done", category: category, icon: icon))

        return TaskCardSequence(
            id: taskId,
            task: task,
            cards: cards,
            isPaywallGated: false,
            needsWorkflowContinue: qualifying != nil
        )
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

    private static func infoCard(id: String, category: String, icon: String, title: String, body: String) -> TaskCardSpec {
        .info(TaskCardInfoData(
            cardId: id,
            category: category,
            headerIcon: icon,
            title: title,
            body: body,
            primaryLabel: "Continue"
        ))
    }

    private static func summaryCard(id: String, category: String, icon: String) -> TaskCardSpec {
        .summary(TaskCardSummaryData(
            cardId: id,
            category: category,
            headerIcon: icon,
            title: "You're all set!",
            body: "We'll take it from here. You can check on this task anytime in the Tasks tab.",
            primaryLabel: "Done"
        ))
    }
}
