# Peezy copy inventory

Phase F1 dump only. No source copy was rewritten.

## Coverage

- 1281 non-LOCKED literal occurrences from production Swift surfaces across 138 files.
- 687 non-LOCKED literal occurrences from runtime data catalogs and callable user-error payloads across 15 files.
- 1968 total entries. Every entry below records its source file heading, 1-based source line, exact current literal text, and receiving component/runtime context.
- The Swift scan inspected all 207 tracked app Swift files. It excluded `#if DEBUG` and `#Preview` content, preview/harness sources, identifiers, persistence keys/state values, analytics/logging strings, URLs, symbol/asset names, format strings, and other implementation-only literals.
- Data coverage includes FlowEngine definitions, task catalog, callable mini-assessments, provider/ISP display catalogs, and user-visible callable/HTTP error payloads. The placeholder mover seed is developer tooling; seed validation messages, admin notifications, source citations/URLs, aliases, research metadata, prompts, and other developer tooling are not runtime interface copy and are excluded.
- Markdown-only HTML escaping is used for table safety (`&`, `<`, `>`, and `|`); interpolation markers and source wording otherwise remain unchanged.

## LOCKED exclusions (not inventoried)

- `Peezy 4.0/MainInterface/Views/Onboarding/ExplainerView.swift`: the complete five-card explainer and its Next/Let's go actions (file-level locked-copy contract; includes the Phase A2 locked card-five body).
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`: the four reflect-back lines; the move-date flexibility subheader is also excluded here and at its rendering source.
- `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDateType.swift`: flexible-date helper copy.
- `Peezy 4.0/Assessment/AssessmentViews/Questions/NewAddress.swift`: pending-address escape-hatch copy.
- `Peezy 4.0/Assessment/PeezyTheme/AssessmentVisualSystem.swift`: the four locked chapter names: Your move / Your homes / Your people / Your accounts.
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` and `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`: That's today / You're on pace closing copy.
- `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift`: Leave this task dialog title, saved/unsaved bodies, and Leave / Leave anyway / Keep going actions.
- `Peezy 4.0/MainInterface/Views/ProviderActionCard.swift`: the computed notice-deadline sentence pattern.
- `Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift` plus its generated task copy in `TaskActionService.swift`: box-headroom sentence.
- `Peezy 4.0/Tasks/Task Cards/PackingReadinessView.swift`: moving-day overage consequence sentence.
- `Peezy 4.0/Tasks/Task Cards/PackingSessionView.swift`: behind-pace consequence sentence.

## iOS runtime strings

### `Peezy 4.0/Assessment/AssessmentModels/AddressSearchManager.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 66 | <code>, </code> | AddressSearchManager — generated/display copy |
| 86 | <code>\(subThoroughfare) \(thoroughfare)</code> | AddressSearchManager — generated/display copy |
| 103 | <code>, </code> | AddressSearchManager — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 395 | <code>Let's get to know each other. What's your first name?</code> | AssessmentCoordinator — heading/title |
| 401 | <code>When are we moving? If it's not 100% official yet, just drop your best guess below!</code> | AssessmentCoordinator — heading/title |
| 407 | <code>Is your move date flexible?</code> | AssessmentCoordinator — heading/title |
| 416 | <code>Alright, let's talk about your current place. Are you renting or do you own?</code> | AssessmentCoordinator — heading/title |
| 417 | <code>This helps me figure out things like lease breaks, security deposits, or listing prep.</code> | AssessmentCoordinator — heading/title |
| 422 | <code>What kind of place is it?</code> | AssessmentCoordinator — heading/title |
| 428 | <code>What's the address?</code> | AssessmentCoordinator — heading/title |
| 429 | <code>I'll use this for mail forwarding, utilities, change of address—all the stuff you'd normally have to chase down yourself.</code> | AssessmentCoordinator — heading/title |
| 434 | <code>What's access like?</code> | AssessmentCoordinator — heading/title |
| 440 | <code>How many bedrooms at your current place?</code> | AssessmentCoordinator — heading/title |
| 446 | <code>Roughly how big is the place?</code> | AssessmentCoordinator — heading/title |
| 447 | <code>Don't overthink it—a ballpark is perfect.</code> | AssessmentCoordinator — heading/title |
| 452 | <code>How much finished living space are we working with?</code> | AssessmentCoordinator — heading/title |
| 453 | <code>Ballpark is totally fine.</code> | AssessmentCoordinator — heading/title |
| 460 | <code>Now let's talk about where you're headed. Renting or buying?</code> | AssessmentCoordinator — heading/title |
| 466 | <code>What kind of place is the new one?</code> | AssessmentCoordinator — heading/title |
| 472 | <code>What's the new address?</code> | AssessmentCoordinator — heading/title |
| 473 | <code>Same deal—I'll use it to get utilities, internet, and everything else set up before you even walk in the door.</code> | AssessmentCoordinator — heading/title |
| 478 | <code>What's access like?</code> | AssessmentCoordinator — heading/title |
| 484 | <code>How many bedrooms at the new place?</code> | AssessmentCoordinator — heading/title |
| 490 | <code>Are there any items in storage that will be making the move as well?</code> | AssessmentCoordinator — heading/title |
| 496 | <code>How big is the unit?</code> | AssessmentCoordinator — heading/title |
| 502 | <code>How full is it?</code> | AssessmentCoordinator — heading/title |
| 508 | <code>Roughly how big is the new place?</code> | AssessmentCoordinator — heading/title |
| 514 | <code>How much finished living space at the new place?</code> | AssessmentCoordinator — heading/title |
| 522 | <code>Will any children be making the move with you?</code> | AssessmentCoordinator — heading/title |
| 528 | <code>Will any of them need to transfer schools?</code> | AssessmentCoordinator — heading/title |
| 534 | <code>What about any in daycare?</code> | AssessmentCoordinator — heading/title |
| 540 | <code>Got any pets that see a vet?</code> | AssessmentCoordinator — heading/title |
| 546 | <code>Will any vehicles be moving with you?</code> | AssessmentCoordinator — heading/title |
| 554 | <code>Now let's talk about any professional help you might need.</code> | AssessmentCoordinator — heading/title |
| 555 | <code>We'll ask about services you're planning to hire or even just interested in receiving quotes from — movers, packers, cleaners, and more.</code> | AssessmentCoordinator — heading/title |
| 560 | <code>Would you like quotes for professional movers?</code> | AssessmentCoordinator — heading/title |
| 566 | <code>Are you planning to rent a moving truck, or do you have that covered?</code> | AssessmentCoordinator — heading/title |
| 572 | <code>Any items you're planning to part with before the move?</code> | AssessmentCoordinator — heading/title |
| 573 | <code>Clothes, furniture, electronics — anything you don't want making the trip.</code> | AssessmentCoordinator — heading/title |
| 578 | <code>Are you planning to sell any of those items?</code> | AssessmentCoordinator — heading/title |
| 579 | <code>We can assist with that process as well as plan b if they don't sell.</code> | AssessmentCoordinator — heading/title |
| 584 | <code>And for the final deep clean of your current home, would you like to get some quotes for professional cleaners?</code> | AssessmentCoordinator — heading/title |
| 592 | <code>Time to make sure everyone knows where to find you.</code> | AssessmentCoordinator — heading/title |
| 593 | <code>You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider in your area, we've got you covered.</code> | AssessmentCoordinator — heading/title |
| 598 | <code>Let's start with finance related accounts you might have.</code> | AssessmentCoordinator — heading/title |
| 599 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | AssessmentCoordinator — heading/title |
| 604 | <code>Now for any health-related accounts?</code> | AssessmentCoordinator — heading/title |
| 605 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | AssessmentCoordinator — heading/title |
| 610 | <code>And lastly, do you have any wellness-related memberships?</code> | AssessmentCoordinator — heading/title |
| 611 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | AssessmentCoordinator — heading/title |
| 618 | <code>Before we get to the fun stuff, we'd love to know what put Peezy on your radar?</code> | AssessmentCoordinator — heading/title |

### `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 368 | <code>No authenticated user found. Please sign in and try again.</code> | AssessmentError — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 94 | <code>\(chapterProgress.position) of \(chapterProgress.total)</code> | AssessmentFlowView — screen text |
| 124 | <code>\(chapter.title), question \(chapterProgress.position) of \(chapterProgress.total)</code> | AssessmentFlowView — accessibility copy |

### `Peezy 4.0/Assessment/AssessmentModels/MultiSelectTile.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 53 | <code>\(count)</code> | MultiSelectTile — screen text |

### `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 66 | <code>Unknown</code> | TaskGenerationService — heading/title |

### `Peezy 4.0/Assessment/AssessmentViews/Components/Datepickertemplate.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 68 | <code>Select Move Date</code> | DatePickerTemplate — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AssessmentIntroView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 18 | <code>Welcome to the easy part</code> | AssessmentIntroView — heading/title |
| 19 | <code>You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move.</code> | AssessmentIntroView — generated/display copy |
| 55 | <code>Just a quick 90 second setup</code> | AssessmentIntroView — screen text |
| 63 | <code>Take the first step</code> | AssessmentIntroView — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/GeneratingView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 33 | <code>Analyzing your move timeline...</code> | GeneratingView — generated/display copy |
| 34 | <code>Checking logistics requirements...</code> | GeneratingView — generated/display copy |
| 35 | <code>Evaluating your household needs...</code> | GeneratingView — generated/display copy |
| 36 | <code>Building your personalized task list...</code> | GeneratingView — generated/display copy |
| 37 | <code>Matching vendor categories...</code> | GeneratingView — generated/display copy |
| 38 | <code>Prioritizing by your move date...</code> | GeneratingView — generated/display copy |
| 39 | <code>Finalizing your custom plan...</code> | GeneratingView — generated/display copy |
| 72 | <code>\(Int(progress))%</code> | GeneratingView — screen text |

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/ReadyView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 56 | <code>Your task list is ready</code> | ReadyView — screen text |
| 60 | <code>We've organized everything you need for a smooth move.</code> | ReadyView — screen text |
| 67 | <code>See Your Custom Plan</code> | ReadyView — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/SummaryView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 41 | <code>\nPersonalized Moving Plan</code> | SummaryView — screen text |
| 46 | <code>Here's what we built for you</code> | SummaryView — screen text |
| 53 | <code>\(taskCount)</code> | SummaryView — screen text |
| 63 | <code>personalized tasks</code> | SummaryView — screen text |
| 73 | <code>Let's Get Started</code> | SummaryView — generated/display copy |
| 93 | <code>Your</code> | SummaryView — generated/display copy |
| 95 | <code>'s</code> | SummaryView — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/AddressAutocompleteView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 187 | <code>Apt / Unit #</code> | UnitNumberField — field placeholder/helper |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/Addresschangeintro.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 10 | <code>Time to make sure everyone knows where to find you.</code> | AddressChangeIntro — heading/title |
| 11 | <code>You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider, we've got you covered.</code> | AddressChangeIntro — helper/subtext |
| 12 | <code>Continue</code> | AddressChangeIntro — button/action label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/AnyKids.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 8 | <code>Will any children be making the move with you?</code> | AnyKids — option/list label |
| 10 | <code>No</code> | AnyKids — option/list label |
| 10 | <code>Yes</code> | AnyKids — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/ChildrenInDaycare.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>What about any in daycare?</code> | ChildrenInDaycare — option/list label |
| 6 | <code>No</code> | ChildrenInDaycare — option/list label |
| 6 | <code>Yes</code> | ChildrenInDaycare — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/ChildrenInSchool.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Will any of them need to transfer schools?</code> | ChildrenInSchool — option/list label |
| 6 | <code>No</code> | ChildrenInSchool — option/list label |
| 6 | <code>Yes</code> | ChildrenInSchool — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentAddress.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>What's the current address?</code> | CurrentAddress — heading/title |
| 10 | <code>I'll use this for mail forwarding, utilities, and more.</code> | CurrentAddress — helper/subtext |
| 11 | <code>Start typing your address</code> | CurrentAddress — field placeholder/helper |
| 12 | <code>Continue</code> | CurrentAddress — button/action label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentBedrooms.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 6 | <code>How many bedrooms at your current place?</code> | CurrentBedrooms — option/list label |
| 8 | <code>1 Bedroom</code> | CurrentBedrooms — option/list label |
| 8 | <code>2 Bedrooms</code> | CurrentBedrooms — option/list label |
| 8 | <code>3 Bedrooms</code> | CurrentBedrooms — option/list label |
| 8 | <code>4 Bedrooms</code> | CurrentBedrooms — option/list label |
| 8 | <code>5 Bedrooms</code> | CurrentBedrooms — option/list label |
| 8 | <code>6+ Bedrooms</code> | CurrentBedrooms — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentDwellingType.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>What kind of place are you in now?</code> | CurrentDwellingType — option/list label |
| 6 | <code>Apartment</code> | CurrentDwellingType — option/list label |
| 6 | <code>Condo</code> | CurrentDwellingType — option/list label |
| 6 | <code>House</code> | CurrentDwellingType — option/list label |
| 6 | <code>Townhouse</code> | CurrentDwellingType — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentFloorAccess.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>What's access like at the current place?</code> | CurrentFloorAccess — option/list label |
| 6 | <code>Elevator</code> | CurrentFloorAccess — option/list label |
| 6 | <code>Ground Floor</code> | CurrentFloorAccess — option/list label |
| 6 | <code>Reserved Elevator</code> | CurrentFloorAccess — option/list label |
| 6 | <code>Stairs</code> | CurrentFloorAccess — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentRentOrOwn.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Are you currently renting or do you own?</code> | CurrentRentOrOwn — option/list label |
| 6 | <code>Own</code> | CurrentRentOrOwn — option/list label |
| 6 | <code>Rent</code> | CurrentRentOrOwn — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/FinancialInstitutions.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>Let's start with finance related accounts you might have.</code> | FinancialInstitutions — heading/title |
| 6 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | FinancialInstitutions — helper/subtext |
| 7 | <code>Continue</code> | FinancialInstitutions — button/action label |
| 11 | <code>Bank / Credit Union</code> | FinancialInstitutions — option/list label |
| 12 | <code>Credit Card</code> | FinancialInstitutions — option/list label |
| 13 | <code>Investment Account</code> | FinancialInstitutions — generated/display copy |
| 14 | <code>Student Loans</code> | FinancialInstitutions — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/FitnessWellness.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>And lastly, do you have any wellness-related memberships?</code> | FitnessWellness — heading/title |
| 6 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | FitnessWellness — helper/subtext |
| 7 | <code>Continue</code> | FitnessWellness — button/action label |
| 11 | <code>Gym / CrossFit</code> | FitnessWellness — option/list label |
| 12 | <code>Yoga / Pilates</code> | FitnessWellness — option/list label |
| 13 | <code>Spin / Cycling</code> | FitnessWellness — generated/display copy |
| 14 | <code>Massage / Spa</code> | FitnessWellness — generated/display copy |
| 15 | <code>Country Club / Golf</code> | FitnessWellness — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HasDeclutter.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Any items you're planning to part with before the move?</code> | HasDeclutter — option/list label |
| 5 | <code>Clothes, furniture, electronics — anything you don't want making the trip.</code> | HasDeclutter — option/list label |
| 6 | <code>No</code> | HasDeclutter — option/list label |
| 6 | <code>Yes</code> | HasDeclutter — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HasStorage.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 7 | <code>Are there any items in storage that will be making the move as well?</code> | HasStorage — option/list label |
| 9 | <code>No</code> | HasStorage — option/list label |
| 9 | <code>Yes</code> | HasStorage — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HasVehicles.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 7 | <code>Will any vehicles be moving with you?</code> | HasVehicles — option/list label |
| 9 | <code>No</code> | HasVehicles — option/list label |
| 9 | <code>Yes</code> | HasVehicles — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HasVet.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Got any pets that see a vet?</code> | HasVet — option/list label |
| 6 | <code>No</code> | HasVet — option/list label |
| 6 | <code>Yes</code> | HasVet — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HealthcareProviders.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>Now for any health-related accounts?</code> | HealthcareProviders — heading/title |
| 6 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | HealthcareProviders — helper/subtext |
| 7 | <code>Continue</code> | HealthcareProviders — button/action label |
| 11 | <code>Doctor</code> | HealthcareProviders — option/list label |
| 12 | <code>Dentist</code> | HealthcareProviders — option/list label |
| 13 | <code>Specialists</code> | HealthcareProviders — generated/display copy |
| 14 | <code>Pharmacy</code> | HealthcareProviders — generated/display copy |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HireCleaners.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>And for the final deep clean of your current home, would you like quotes for professional cleaners?</code> | HireCleaners — option/list label |
| 6 | <code>No</code> | HireCleaners — option/list label |
| 6 | <code>Yes</code> | HireCleaners — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HireMovers.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 19 | <code>Would you like quotes for professional movers?</code> | HireMovers — option/list label |
| 21 | <code>No</code> | HireMovers — option/list label |
| 21 | <code>Yes</code> | HireMovers — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HowHeard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>How did you hear about Peezy?</code> | HowHeard — option/list label |
| 6 | <code>Friend or Family</code> | HowHeard — option/list label |
| 6 | <code>Google Search</code> | HowHeard — option/list label |
| 6 | <code>Moving Company</code> | HowHeard — option/list label |
| 6 | <code>Other</code> | HowHeard — option/list label |
| 6 | <code>Real Estate Agent</code> | HowHeard — option/list label |
| 6 | <code>Social Media</code> | HowHeard — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDate.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>When's the big day?</code> | MoveDate — heading/title |
| 10 | <code>If you're unsure, put your best guess and you can update it later.</code> | MoveDate — helper/subtext |
| 11 | <code>Continue</code> | MoveDate — button/action label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDateType.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 8 | <code>Is your move date flexible?</code> | MoveDateType — option/list label |
| 10 | <code>Flexible</code> | MoveDateType — option/list label |
| 10 | <code>Strict</code> | MoveDateType — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/NewAddress.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>What's the new address?</code> | NewAddress — heading/title |
| 10 | <code>I'll use this to get utilities, internet, and everything else set up before you walk in.</code> | NewAddress — helper/subtext |
| 11 | <code>Start typing your address</code> | NewAddress — field placeholder/helper |
| 12 | <code>Continue</code> | NewAddress — button/action label |
| 98 | <code>Actually, I have the address</code> | NewAddress — screen text |
| 98 | <code>I don't have it yet</code> | NewAddress — screen text |
| 145 | <code>City, state, or ZIP (optional)</code> | NewAddress — field placeholder/helper |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/NewBedrooms.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 6 | <code>How many bedrooms at the new place?</code> | NewBedrooms — option/list label |
| 8 | <code>1 Bedroom</code> | NewBedrooms — option/list label |
| 8 | <code>2 Bedrooms</code> | NewBedrooms — option/list label |
| 8 | <code>3 Bedrooms</code> | NewBedrooms — option/list label |
| 8 | <code>4 Bedrooms</code> | NewBedrooms — option/list label |
| 8 | <code>5 Bedrooms</code> | NewBedrooms — option/list label |
| 8 | <code>6+ Bedrooms</code> | NewBedrooms — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/NewDwellingType.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>What kind of place is the new one?</code> | NewDwellingType — option/list label |
| 6 | <code>Apartment</code> | NewDwellingType — option/list label |
| 6 | <code>Condo</code> | NewDwellingType — option/list label |
| 6 | <code>House</code> | NewDwellingType — option/list label |
| 6 | <code>Townhouse</code> | NewDwellingType — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/NewFloorAccess.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>What's access like at the new place?</code> | NewFloorAccess — option/list label |
| 6 | <code>Elevator</code> | NewFloorAccess — option/list label |
| 6 | <code>Ground Floor</code> | NewFloorAccess — option/list label |
| 6 | <code>Reserved Elevator</code> | NewFloorAccess — option/list label |
| 6 | <code>Stairs</code> | NewFloorAccess — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/NewRentOrOwn.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>And the new place — renting or buying?</code> | NewRentOrOwn — option/list label |
| 6 | <code>Buying</code> | NewRentOrOwn — option/list label |
| 6 | <code>Renting</code> | NewRentOrOwn — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/Servicesintro.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 10 | <code>Time to talk services.</code> | ServicesIntro — heading/title |
| 11 | <code>We'll ask about services you might want help with — movers, packers, cleaners, and more.</code> | ServicesIntro — helper/subtext |
| 12 | <code>Continue</code> | ServicesIntro — button/action label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/StorageFullness.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>How full is it?</code> | StorageFullness — option/list label |
| 7 | <code>1/2</code> | StorageFullness — option/list label |
| 7 | <code>1/4</code> | StorageFullness — option/list label |
| 7 | <code>3/4</code> | StorageFullness — option/list label |
| 7 | <code>Full</code> | StorageFullness — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/StorageSize.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>How big is the unit?</code> | StorageSize — option/list label |
| 7 | <code>Large</code> | StorageSize — option/list label |
| 7 | <code>Medium</code> | StorageSize — option/list label |
| 7 | <code>Small</code> | StorageSize — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/TruckRental.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Are you planning to rent a moving truck?</code> | TruckRental — option/list label |
| 6 | <code>No</code> | TruckRental — option/list label |
| 6 | <code>Yes</code> | TruckRental — option/list label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/UserName.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>What's your first name?</code> | UserName — heading/title |
| 11 | <code>First name</code> | UserName — field placeholder/helper |
| 12 | <code>Continue</code> | UserName — button/action label |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/WantToSell.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 7 | <code>Are you planning to sell any of those items?</code> | WantToSell — option/list label |
| 8 | <code>We can assist with that process as well as plan b if they don't sell.</code> | WantToSell — option/list label |
| 9 | <code>No</code> | WantToSell — option/list label |
| 9 | <code>Yes</code> | WantToSell — option/list label |

### `Peezy 4.0/Auth/AuthView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 45 | <code>Moving made peezy.</code> | AuthLoadingState — generated/display copy |
| 45 | <code>Your move, on autopilot.</code> | AuthLoadingState — generated/display copy |
| 96 | <code>Continue with Google</code> | AuthLoadingState — heading/title |
| 115 | <code>Continue with Email</code> | AuthLoadingState — heading/title |
| 132 | <code>Already have an account?</code> | AuthLoadingState — screen text |
| 134 | <code>Log in</code> | AuthLoadingState — screen text |

### `Peezy 4.0/Auth/AuthViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 55 | <code>Invalid state: A login callback was received, but no login request was sent.</code> | AuthViewModel — error message |
| 60 | <code>Unable to fetch identity token</code> | AuthViewModel — error message |
| 65 | <code>Unable to serialize token string from data</code> | AuthViewModel — error message |
| 110 | <code>Unable to process Apple Sign-In credential</code> | AuthViewModel — error message |
| 123 | <code>Missing client ID</code> | AuthViewModel — error message |
| 133 | <code>No root view controller</code> | AuthViewModel — error message |
| 146 | <code>Missing ID token</code> | AuthViewModel — error message |

### `Peezy 4.0/Auth/LogInView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 43 | <code>Welcome back</code> | LoginView — screen text |
| 47 | <code>Log in to continue your move</code> | LoginView — screen text |
| 57 | <code>Email</code> | LoginView — generated/display copy |
| 58 | <code>your@email.com</code> | LoginView — field placeholder/helper |
| 66 | <code>Password</code> | LoginView — generated/display copy |
| 67 | <code>Enter your password</code> | LoginView — field placeholder/helper |
| 78 | <code>Log in</code> | LoginView — heading/title |
| 90 | <code>Please enter your email address first</code> | LoginView — error message |
| 96 | <code>Forgot password?</code> | LoginView — alert/confirmation |
| 108 | <code>Don't have an account?</code> | LoginView — screen text |
| 110 | <code>Sign up</code> | LoginView — screen text |
| 131 | <code>Error</code> | LoginView — error message |
| 132 | <code>OK</code> | LoginView — button/action label |
| 136 | <code>Reset password</code> | LoginView — error message |
| 137 | <code>Send Reset Email</code> | LoginView — button/action label |
| 143 | <code>Password reset email sent to \(email)</code> | LoginView — error message |
| 148 | <code>Cancel</code> | LoginView — button/action label |
| 150 | <code>Send a password reset email to \(email)?</code> | LoginView — alert/confirmation |
| 152 | <code>Email sent</code> | LoginView — alert/confirmation |
| 153 | <code>OK</code> | LoginView — button/action label |

### `Peezy 4.0/Auth/SignUpView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 42 | <code>Create Account</code> | SignUpView — screen text |
| 46 | <code>Sign up to get started with Peezy</code> | SignUpView — screen text |
| 56 | <code>Email</code> | SignUpView — generated/display copy |
| 57 | <code>your@email.com</code> | SignUpView — field placeholder/helper |
| 65 | <code>Password</code> | SignUpView — generated/display copy |
| 66 | <code>Min. 6 characters</code> | SignUpView — field placeholder/helper |
| 74 | <code>Confirm Password</code> | SignUpView — generated/display copy |
| 75 | <code>Re-enter password</code> | SignUpView — field placeholder/helper |
| 84 | <code>Passwords do not match</code> | SignUpView — error message |
| 95 | <code>Sign up</code> | SignUpView — heading/title |
| 109 | <code>Already have an account?</code> | SignUpView — screen text |
| 111 | <code>Log in</code> | SignUpView — screen text |
| 131 | <code>Error</code> | SignUpView — error message |
| 132 | <code>OK</code> | SignUpView — button/action label |
| 142 | <code>Passwords do not match</code> | SignUpView — error message |

### `Peezy 4.0/Auth/TypewriterText.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 38 | <code>&#124;</code> | AnimationPhase — screen text |

### `Peezy 4.0/Inventory/Models/InventoryCoverage.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 69 | <code>Living Room</code> | InventoryCoverage — generated/display copy |
| 70 | <code>Kitchen</code> | InventoryCoverage — generated/display copy |
| 71 | <code>Bathroom</code> | InventoryCoverage — generated/display copy |
| 77 | <code>Bedroom</code> | InventoryCoverage — generated/display copy |
| 77 | <code>Bedroom \(index)</code> | InventoryCoverage — generated/display copy |
| 87 | <code>Garage</code> | InventoryCoverage — generated/display copy |
| 88 | <code>Basement</code> | InventoryCoverage — generated/display copy |

### `Peezy 4.0/Inventory/Models/InventorySessionManager.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 277 | <code>Couldn't save that coverage answer. Please try again.</code> | is — error message |
| 286 | <code>You must be signed in to scan inventory</code> | is — error message |
| 297 | <code>Uploading frames...</code> | is — generated/display copy |
| 329 | <code>Analyzing room...</code> | is — generated/display copy |
| 420 | <code>Processing failed</code> | is — error message |
| 425 | <code>Analyzing room...</code> | is — generated/display copy |
| 575 | <code>Not signed in</code> | is — generated/display copy |

### `Peezy 4.0/Inventory/Services/FrameExtractionService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 29 | <code>Cannot load video at \(videoURL.path): \(error.localizedDescription)</code> | FrameExtractionService — error message |
| 129 | <code>Video has zero duration</code> | FrameExtractionError — generated/display copy |
| 130 | <code>No frames could be extracted from the video</code> | FrameExtractionError — generated/display copy |

### `Peezy 4.0/Inventory/Services/InventoryAPIClient.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 27 | <code>Server returned success=false</code> | InventoryAPIClient — error message |
| 51 | <code>Package send returned success=false</code> | InventoryAPIClient — error message |
| 71 | <code>You must be signed in to scan inventory</code> | InventoryError — error message |
| 72 | <code>Invalid request: \(msg)</code> | InventoryError — error message |
| 73 | <code>Processing failed: \(msg)</code> | InventoryError — error message |
| 74 | <code>Network error: \(err.localizedDescription)</code> | InventoryError — error message |
| 75 | <code>Upload failed: \(msg)</code> | InventoryError — error message |

### `Peezy 4.0/Inventory/Services/InventoryStorageService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 219 | <code>No frames provided for upload</code> | InventoryStorageError — generated/display copy |
| 221 | <code>Firestore write failed: \(message)</code> | InventoryStorageError — generated/display copy |

### `Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 105 | <code>Looks Good — \(moveCount) item\(moveCount == 1 ? "" : "s")</code> | InventoryReviewViewModel — generated/display copy |

### `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 249 | <code>No camera available on this device</code> | CaptureError — error message |
| 250 | <code>Cannot configure camera input</code> | CaptureError — generated/display copy |
| 251 | <code>Cannot configure video recording output</code> | CaptureError — generated/display copy |

### `Peezy 4.0/Inventory/Views/InventoryCameraView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 30 | <code>Peezy AI is scanning...</code> | InventoryCameraView — generated/display copy |
| 31 | <code>Identifying items...</code> | InventoryCameraView — generated/display copy |
| 32 | <code>Keep panning slowly...</code> | InventoryCameraView — generated/display copy |
| 140 | <code>Camera access needed</code> | InventoryCameraView — screen text |
| 144 | <code>Peezy uses your camera to scan rooms and identify what you're moving. You can enable access in iOS Settings.</code> | InventoryCameraView — screen text |
| 154 | <code>Open Settings</code> | InventoryCameraView — generated/display copy |
| 161 | <code>Go back</code> | InventoryCameraView — screen text |
| 264 | <code>peezy</code> | InventoryCameraView — screen text |
| 269 | <code>·</code> | InventoryCameraView — screen text |
| 365 | <code>Stop Recording</code> | InventoryCameraView — screen text |
| 370 | <code>Pan slowly around the room</code> | InventoryCameraView — screen text |
| 414 | <code>Processing frames...</code> | InventoryCameraView — screen text |
| 440 | <code>Dismiss</code> | InventoryCameraView — button/action label |

### `Peezy 4.0/Inventory/Views/InventoryFlowView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 148 | <code>Submitted!</code> | InventoryFlowView — alert/confirmation |
| 149 | <code>Done</code> | InventoryFlowView — button/action label |
| 155 | <code>Your inventory has been submitted. We'll use it to coordinate your move.</code> | InventoryFlowView — screen text |
| 193 | <code>Scan my home</code> | InventoryFlowView — heading/title |
| 226 | <code>Scan my home</code> | InventoryFlowView — heading/title |
| 227 | <code>Here's how it works</code> | InventoryFlowView — heading/title |
| 228 | <code>Pan your camera slowly around each room — about 20 seconds per room. Peezy uses AI (Anthropic Claude) to identify furniture and belongings automatically.\n\nOpen closets and cabinets. Go one room at a time for the best results.\n\nYour scan video frames are sent securely to Anthropic for processing and are not stored or used for AI training. See our Privacy Policy at peezy-1ecrdl.web.app/privacy.html for details.</code> | InventoryFlowView — generated/display copy |
| 229 | <code>Let's go</code> | InventoryFlowView — button/action label |
| 274 | <code>Room saved!</code> | InventoryFlowView — screen text |
| 278 | <code>\(savedItemCount) items in \(savedRoomName)</code> | InventoryFlowView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryItemConfirmView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 67 | <code>\(viewModel.currentIndex + 1) of \(viewModel.itemsToConfirm.count)</code> | InventoryItemConfirmView — screen text |
| 87 | <code>Help us identify a few items</code> | InventoryItemConfirmView — screen text |
| 103 | <code>What is this item?</code> | InventoryItemConfirmView — field placeholder/helper |
| 119 | <code>Is this a **\(item.name)**?</code> | InventoryItemConfirmView — screen text |
| 140 | <code>Cancel</code> | InventoryItemConfirmView — screen text |
| 140 | <code>Not quite</code> | InventoryItemConfirmView — screen text |
| 160 | <code>Save correction</code> | InventoryItemConfirmView — screen text |
| 160 | <code>That's right</code> | InventoryItemConfirmView — screen text |
| 211 | <code>Image unavailable</code> | InventoryItemConfirmView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryLockedView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 42 | <code>Inventory submitted</code> | InventoryLockedView — screen text |
| 46 | <code>\(rooms.count) room\(rooms.count == 1 ? "" : "s") · \(totalItems) item\(totalItems == 1 ? "" : "s")</code> | InventoryLockedView — screen text |
| 50 | <code>Need to make a change? Send us a message in the chat and we'll update it for you.</code> | InventoryLockedView — screen text |
| 70 | <code>\(room.items.count) items</code> | InventoryLockedView — screen text |
| 77 | <code>•</code> | InventoryLockedView — screen text |
| 85 | <code>×\(item.quantity)</code> | InventoryLockedView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryProcessingView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 21 | <code>Uploading frames...</code> | InventoryProcessingView — generated/display copy |
| 22 | <code>Identifying furniture...</code> | InventoryProcessingView — generated/display copy |
| 23 | <code>Counting items...</code> | InventoryProcessingView — generated/display copy |
| 24 | <code>Checking for fragile items...</code> | InventoryProcessingView — generated/display copy |
| 25 | <code>Almost done...</code> | InventoryProcessingView — generated/display copy |

### `Peezy 4.0/Inventory/Views/InventoryRoomHubView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 68 | <code>Delete Room</code> | InventoryRoomHubView — alert/confirmation |
| 69 | <code>Delete</code> | InventoryRoomHubView — button/action label |
| 78 | <code>Cancel</code> | InventoryRoomHubView — button/action label |
| 83 | <code>Remove \(room.name) and its \(room.items.count) items?</code> | InventoryRoomHubView — screen text |
| 86 | <code>Ready to submit?</code> | InventoryRoomHubView — alert/confirmation |
| 87 | <code>Cancel</code> | InventoryRoomHubView — button/action label |
| 88 | <code>Yes, submit</code> | InventoryRoomHubView — button/action label |
| 92 | <code>Are you sure you've scanned all your rooms? Once submitted, you won't be able to add or change rooms. If something changes, message us in the chat.</code> | InventoryRoomHubView — screen text |
| 103 | <code>Your Inventory</code> | InventoryRoomHubView — screen text |
| 111 | <code>\(roomCount) \(roomWord) · \(sessionManager.totalItemCount) \(itemWord)</code> | InventoryRoomHubView — screen text |
| 130 | <code>Scan your first room to start\nbuilding your inventory</code> | InventoryRoomHubView — screen text |
| 158 | <code>Coverage check</code> | InventoryRoomHubView — screen text |
| 162 | <code>Scanned: \(report.scannedRoomNames.joined(separator: ", "))</code> | InventoryRoomHubView — screen text |
| 168 | <code>All expected rooms accounted for</code> | InventoryRoomHubView — option/list label |
| 173 | <code>Not seen: \(report.unresolvedRooms.map(\.displayName).joined(separator: ", "))</code> | InventoryRoomHubView — screen text |
| 190 | <code>Add a clip</code> | InventoryRoomHubView — option/list label |
| 203 | <code>Nothing there</code> | InventoryRoomHubView — screen text |
| 239 | <code>\(room.items.count) \(itemWord)</code> | InventoryRoomHubView — screen text |
| 247 | <code>\(room.items.count)</code> | InventoryRoomHubView — screen text |
| 293 | <code>Scan Another Room</code> | InventoryRoomHubView — screen text |
| 293 | <code>Scan Your First Room</code> | InventoryRoomHubView — screen text |
| 307 | <code>Submit Inventory</code> | InventoryRoomHubView — alert/confirmation |
| 307 | <code>Submitting...</code> | InventoryRoomHubView — alert/confirmation |
| 317 | <code>Finish later</code> | InventoryRoomHubView — screen text |
| 339 | <code>What room are you scanning?</code> | InventoryRoomHubView — screen text |
| 344 | <code>e.g. Living Room</code> | InventoryRoomHubView — field placeholder/helper |
| 360 | <code>Begin Scanning</code> | InventoryRoomHubView — generated/display copy |
| 376 | <code>Cancel</code> | InventoryRoomHubView — button/action label |

### `Peezy 4.0/Inventory/Views/InventoryRoomReviewView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 33 | <code>appliance</code> | InventoryRoomReviewView — generated/display copy |
| 33 | <code>boxes</code> | InventoryRoomReviewView — generated/display copy |
| 33 | <code>decor</code> | InventoryRoomReviewView — generated/display copy |
| 33 | <code>electronics</code> | InventoryRoomReviewView — generated/display copy |
| 33 | <code>furniture</code> | InventoryRoomReviewView — generated/display copy |
| 33 | <code>other</code> | InventoryRoomReviewView — generated/display copy |
| 34 | <code>large</code> | InventoryRoomReviewView — generated/display copy |
| 34 | <code>medium</code> | InventoryRoomReviewView — generated/display copy |
| 34 | <code>oversized</code> | InventoryRoomReviewView — generated/display copy |
| 34 | <code>small</code> | InventoryRoomReviewView — generated/display copy |
| 44 | <code>What item are you adding?</code> | AddItemQuestion — generated/display copy |
| 45 | <code>What kind of item is it?</code> | AddItemQuestion — generated/display copy |
| 46 | <code>Which category fits best?</code> | AddItemQuestion — generated/display copy |
| 47 | <code>What size is it?</code> | AddItemQuestion — generated/display copy |
| 99 | <code>Are you sure you're not moving this?</code> | AddItemQuestion — alert/confirmation |
| 100 | <code>Cancel</code> | AddItemQuestion — button/action label |
| 103 | <code>Remove</code> | AddItemQuestion — button/action label |
| 105 | <code>\(item.name) removed</code> | AddItemQuestion — generated/display copy |
| 109 | <code>\(item.name) will be removed from your inventory.</code> | AddItemQuestion — screen text |
| 132 | <code>\(viewModel.totalItemCount)</code> | AddItemQuestion — screen text |
| 136 | <code> item in </code> | AddItemQuestion — screen text |
| 136 | <code> items in </code> | AddItemQuestion — screen text |
| 158 | <code>Furniture &amp; Large Items</code> | AddItemQuestion — screen text |
| 162 | <code>\(viewModel.furnitureItems.count)</code> | AddItemQuestion — screen text |
| 188 | <code>Boxable Items</code> | AddItemQuestion — screen text |
| 192 | <code>\(viewModel.boxableItems.count)</code> | AddItemQuestion — screen text |
| 214 | <code>Hide details</code> | AddItemQuestion — screen text |
| 214 | <code>See all items</code> | AddItemQuestion — screen text |
| 232 | <code>×\(item.quantity)</code> | AddItemQuestion — screen text |
| 287 | <code>Fragile</code> | AddItemQuestion — screen text |
| 298 | <code>Value</code> | AddItemQuestion — screen text |
| 311 | <code>×\(item.quantity)</code> | AddItemQuestion — screen text |
| 315 | <code>Quantity \(item.quantity)</code> | AddItemQuestion — accessibility copy |
| 335 | <code>Delete</code> | AddItemQuestion — option/list label |
| 351 | <code>Remove \(item.name)</code> | AddItemQuestion — accessibility copy |
| 368 | <code>Add</code> | AddItemQuestion — screen text |
| 409 | <code>Re-scan this room</code> | AddItemQuestion — screen text |
| 430 | <code>×\(item.quantity)</code> | AddItemQuestion — screen text |
| 448 | <code>Question \(addItemQuestionIndex + 1) of \(AddItemQuestion.allCases.count)</code> | AddItemQuestion — screen text |
| 464 | <code>Add</code> | AddItemQuestion — generated/display copy |
| 464 | <code>Continue</code> | AddItemQuestion — generated/display copy |
| 471 | <code>Add Item</code> | AddItemQuestion — heading/title |
| 475 | <code>Cancel</code> | AddItemQuestion — button/action label |
| 482 | <code>Back</code> | AddItemQuestion — button/action label |
| 499 | <code>e.g. Floor Lamp</code> | AddItemQuestion — field placeholder/helper |
| 503 | <code>Tier</code> | AddItemQuestion — generated/display copy |
| 504 | <code>Furniture / Large Item</code> | AddItemQuestion — screen text |
| 505 | <code>Packable / Goes in a Box</code> | AddItemQuestion — screen text |
| 510 | <code>Category</code> | AddItemQuestion — generated/display copy |
| 519 | <code>Size</code> | AddItemQuestion — generated/display copy |

### `Peezy 4.0/MainInterface/Models/BoxReturnService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 116 | <code>Pick up \(returned) returned boxes</code> | BoxReturnService — heading/title |
| 134 | <code>Sign in before saving your box count.</code> | BoxReturnServiceError — generated/display copy |
| 136 | <code>Peezy couldn't find the packing kit you ordered.</code> | BoxReturnServiceError — generated/display copy |
| 138 | <code>Enter a box count of zero or more.</code> | BoxReturnServiceError — generated/display copy |
| 140 | <code>Add at least one box before requesting pickup.</code> | BoxReturnServiceError — generated/display copy |
| 142 | <code>Peezy couldn't verify that box count. Please try again.</code> | BoxReturnServiceError — generated/display copy |
| 144 | <code>Your count was saved, but the pickup request didn't go through. Please try again.</code> | BoxReturnServiceError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/CheckInService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 154 | <code>Peezy couldn't save that check-in. Please try again.</code> | CheckInServiceError — error message |

### `Peezy 4.0/MainInterface/Models/ISPPlanService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 40 | <code>Provider confirms address availability and final terms</code> | ISPPlan — generated/display copy |
| 98 | <code>ISP plan \(documentID) has an invalid \(field) field.</code> | ISPPlanError — generated/display copy |
| 100 | <code>No internet plans are available right now.</code> | ISPPlanError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/KitEstimator.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 91 | <code>\(large) large</code> | SuppliesKit — generated/display copy |
| 91 | <code>\(medium) medium</code> | SuppliesKit — generated/display copy |
| 91 | <code>\(small) small</code> | SuppliesKit — generated/display copy |
| 92 | <code>\(dishPack) dish pack</code> | SuppliesKit — generated/display copy |
| 92 | <code>\(tape) tape</code> | SuppliesKit — generated/display copy |
| 92 | <code>\(wardrobe) wardrobe</code> | SuppliesKit — generated/display copy |
| 93 | <code>\(mattressBags) mattress bags</code> | SuppliesKit — generated/display copy |
| 93 | <code>\(paper) paper</code> | SuppliesKit — generated/display copy |
| 93 | <code>\(wrap) wrap</code> | SuppliesKit — generated/display copy |
| 94 | <code>, </code> | SuppliesKit — generated/display copy |

### `Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 24 | <code>A custom quote for the long haul</code> | MoversConciergeReason — heading/title |
| 25 | <code>Long-distance moves get a hand-built quote from us — you'll have it within a day.</code> | MoversConciergeReason — generated/display copy |
| 29 | <code>This is a big one.</code> | MoversConciergeReason — heading/title |
| 30 | <code>Big moves deserve a hand-built quote — we'll have yours within a day.</code> | MoversConciergeReason — generated/display copy |
| 50 | <code>1 Bedroom</code> | MoversFlowViewModel — generated/display copy |
| 51 | <code>1 Bedroom</code> | MoversFlowViewModel — generated/display copy |
| 53 | <code>Small</code> | MoversFlowViewModel — generated/display copy |
| 54 | <code>1/2</code> | MoversFlowViewModel — generated/display copy |
| 83 | <code>Calculating scope</code> | MoversFlowViewModel — generated/display copy |
| 84 | <code>~\(Int(scope.cubicFeet.rounded())) cu ft</code> | MoversFlowViewModel — generated/display copy |
| 88 | <code>Home details pending</code> | MoversFlowViewModel — generated/display copy |
| 92 | <code>\(Self.shortAccess(originAccessAnswer)) at origin · \(Self.shortAccess(destinationAccessAnswer)) at destination</code> | MoversFlowViewModel — generated/display copy |
| 97 | <code> · moving-day stop</code> | MoversFlowViewModel — generated/display copy |
| 98 | <code>\(storageSize) storage · \(storageFullness) full\(stop)</code> | MoversFlowViewModel — generated/display copy |
| 102 | <code>home details</code> | MoversFlowViewModel — generated/display copy |
| 102 | <code>your scan</code> | MoversFlowViewModel — generated/display copy |
| 115 | <code>Sign in again to continue booking your movers.</code> | MoversFlowViewModel — generated/display copy |
| 121 | <code>Your move details are missing. Add both addresses in Settings, then try again.</code> | MoversFlowViewModel — generated/display copy |
| 146 | <code>The scan finished without any move items. Try the scan again or use home details.</code> | MoversFlowViewModel — generated/display copy |
| 368 | <code>We couldn't send the booking request. Nothing was booked—please try again. \(error.localizedDescription)</code> | MoversFlowViewModel — error message |
| 403 | <code>We couldn't send the quote request. Nothing was submitted—please try again. \(error.localizedDescription)</code> | MoversFlowViewModel — error message |
| 477 | <code>1 Bedroom</code> | MoversFlowViewModel — generated/display copy |
| 478 | <code>1 Bedroom</code> | MoversFlowViewModel — generated/display copy |
| 577 | <code>Medium</code> | MoversFlowViewModel — generated/display copy |
| 578 | <code>Large</code> | MoversFlowViewModel — generated/display copy |
| 579 | <code>Small</code> | MoversFlowViewModel — generated/display copy |
| 585 | <code>1/4</code> | MoversFlowViewModel — generated/display copy |
| 586 | <code>3/4</code> | MoversFlowViewModel — generated/display copy |
| 587 | <code>Full</code> | MoversFlowViewModel — generated/display copy |
| 588 | <code>1/2</code> | MoversFlowViewModel — generated/display copy |
| 594 | <code>Ground Floor</code> | MoversFlowViewModel — generated/display copy |
| 595 | <code>Stairs</code> | MoversFlowViewModel — generated/display copy |
| 596 | <code>Elevator</code> | MoversFlowViewModel — generated/display copy |
| 597 | <code>Reserved Elevator</code> | MoversFlowViewModel — generated/display copy |
| 603 | <code>access TBD</code> | MoversFlowViewModel — generated/display copy |
| 616 | <code>Your identity details could not be loaded.</code> | FlowError — error message |
| 617 | <code>Your move scope could not be calculated.</code> | FlowError — generated/display copy |
| 618 | <code>Add your current address before comparing movers.</code> | FlowError — generated/display copy |
| 619 | <code>We couldn't verify which movers serve your current address.</code> | FlowError — generated/display copy |
| 620 | <code>No active movers currently cover this address.</code> | FlowError — generated/display copy |
| 621 | <code>The booking service did not accept the request.</code> | FlowError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/MoversVendorQuote.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 19 | <code>\(estimate.range.low.formatted(.currency(code: "USD").precision(.fractionLength(0))))–\(estimate.range.high.formatted(.currency(code: "USD").precision(.fractionLength(0))))</code> | MoversVendorQuote — generated/display copy |
| 20 | <code>\(estimate.typicalHours.formatted(.number.precision(.fractionLength(1)))) hours · \(estimate.crew)-person team</code> | MoversVendorQuote — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PackingConstants.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 39 | <code>Medications, chargers, toiletries, clothes, and move-day documents</code> | PackingConstants — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PackingPlanEngine.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 237 | <code>\(completedSession.roomLabel) done — \(completedRooms.count) of \(roomNames.count) rooms packed. On pace for \(moveDate).</code> | WorkUnit — generated/display copy |
| 310 | <code>\(entry.roomName) non-essentials</code> | WorkUnit — generated/display copy |
| 311 | <code>\(entry.roomName) essentials</code> | WorkUnit — generated/display copy |
| 375 | <code>\(label) — part \(index + 1)</code> | WorkUnit — generated/display copy |
| 422 | <code>\($0.quantity)× \($0.name)</code> | WorkUnit — generated/display copy |
| 427 | <code>First-night bag</code> | WorkUnit — generated/display copy |
| 453 | <code> + </code> | WorkUnit — generated/display copy |
| 496 | <code>\(count)× \(name)</code> | WorkUnit — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PeezyClient.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 234 | <code>Invalid URL configuration</code> | PeezyError — error message |
| 236 | <code>Failed to encode request: \(error.localizedDescription)</code> | PeezyError — error message |
| 238 | <code>Network error: \(error.localizedDescription)</code> | PeezyError — error message |
| 240 | <code>Invalid response from server</code> | PeezyError — error message |
| 242 | <code>HTTP error \(statusCode): \(body ?? "No body")</code> | PeezyError — error message |
| 244 | <code>Failed to decode response: \(error.localizedDescription). Body: \(body ?? "nil")</code> | PeezyError — error message |

### `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 104 | <code>Good morning</code> | HomeState — generated/display copy |
| 105 | <code>Good afternoon</code> | HomeState — generated/display copy |
| 106 | <code>Good evening</code> | HomeState — generated/display copy |
| 107 | <code>Hey</code> | HomeState — generated/display copy |
| 109 | <code>\(greeting), \(name).</code> | HomeState — generated/display copy |
| 109 | <code>\(greeting).</code> | HomeState — generated/display copy |
| 126 | <code>Welcome!</code> | HomeState — generated/display copy |
| 126 | <code>Welcome, \(name)!</code> | HomeState — generated/display copy |
| 130 | <code>You're all caught up for today!</code> | HomeState — generated/display copy |
| 131 | <code>task</code> | HomeState — generated/display copy |
| 131 | <code>tasks</code> | HomeState — generated/display copy |
| 132 | <code>Just \(dailyTarget) \(taskWord) to knock out today!</code> | HomeState — generated/display copy |
| 138 | <code>You're all caught up for today!</code> | HomeState — generated/display copy |
| 139 | <code>You've knocked out all \(dailyTarget) for today!</code> | HomeState — generated/display copy |
| 140 | <code>task</code> | HomeState — generated/display copy |
| 140 | <code>tasks</code> | HomeState — generated/display copy |
| 141 | <code>You've done \(completed) of \(dailyTarget) today — \(remaining) \(taskWord) to go.</code> | HomeState — generated/display copy |
| 146 | <code>Welcome back!</code> | HomeState — generated/display copy |
| 146 | <code>Welcome back, \(name)!</code> | HomeState — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PeezyIdentity.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 31 | <code> \(unit)</code> | PeezyAddress — generated/display copy |
| 32 | <code> </code> | PeezyAddress — generated/display copy |
| 33 | <code>, </code> | PeezyAddress — generated/display copy |
| 58 | <code>-</code> | PeezyAddress — generated/display copy |
| 66 | <code>, </code> | PeezyAddress — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PricingEngine.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 32 | <code>piano</code> | SpecialtyItem — generated/display copy |
| 33 | <code>safe</code> | SpecialtyItem — generated/display copy |
| 34 | <code>pool table</code> | SpecialtyItem — generated/display copy |
| 35 | <code>oversized appliance</code> | SpecialtyItem — generated/display copy |
| 36 | <code>treadmill</code> | SpecialtyItem — generated/display copy |
| 37 | <code>marble tops</code> | SpecialtyItem — generated/display copy |
| 301 | <code>Sized so your move wraps in one solid morning — not a marathon.</code> | PricingEngine — generated/display copy |
| 359 | <code>Includes what scans can't see — closets, cabinets, drawers.</code> | PricingEngine — generated/display copy |
| 361 | <code>Unpacked boxes</code> | PricingEngine — generated/display copy |
| 363 | <code>Unreserved elevator at origin</code> | PricingEngine — generated/display copy |
| 366 | <code>Unreserved elevator at destination</code> | PricingEngine — generated/display copy |
| 368 | <code>Long carry at origin</code> | PricingEngine — generated/display copy |
| 369 | <code>Long carry at destination</code> | PricingEngine — generated/display copy |
| 371 | <code>Undisclosed stairs or access</code> | PricingEngine — generated/display copy |
| 374 | <code>Some rooms weren't scanned.</code> | PricingEngine — generated/display copy |
| 377 | <code>Storage stop estimated — add the unit's address to tighten this.</code> | PricingEngine — generated/display copy |
| 391 | <code>Includes \(item.handlingLabel) handling</code> | PricingEngine — generated/display copy |

### `Peezy 4.0/MainInterface/Models/ProviderDirectoryService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 58 | <code>Provider</code> | ProviderResolution — generated/display copy |

### `Peezy 4.0/MainInterface/Models/ReadinessGate.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 14 | <code>All packing sessions complete</code> | ReadinessItem — generated/display copy |
| 15 | <code>Furniture disassembled</code> | ReadinessItem — generated/display copy |
| 16 | <code>Elevator and parking reserved</code> | ReadinessItem — generated/display copy |
| 17 | <code>Moving path clear</code> | ReadinessItem — generated/display copy |
| 18 | <code>First-night bag set aside</code> | ReadinessItem — generated/display copy |

### `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 98 | <code>Subscription not available.</code> | PurchaseError — error message |
| 101 | <code>Purchase pending approval.</code> | PurchaseError — error message |
| 102 | <code>Could not verify purchase.</code> | PurchaseError — error message |
| 103 | <code>Network error. Please try again.</code> | PurchaseError — error message |

### `Peezy 4.0/MainInterface/Models/SupportChatService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 52 | <code>Not signed in</code> | SupportChatService — error message |
| 77 | <code>Failed to send: \(error.localizedDescription)</code> | SupportChatService — error message |

### `Peezy 4.0/MainInterface/Models/TaskActionService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 604 | <code>Today: \(session.roomLabel). About \(session.estMinutes) minutes.</code> | TaskActionService — heading/title |
| 605 | <code>Here's what's in it: \(session.itemSummary.joined(separator: ", "))</code> | TaskActionService — generated/display copy |
| 612 | <code>Pack only this session. Peezy will reflow the rest if plans change.</code> | TaskActionService — generated/display copy |
| 613 | <code>One focused packing session keeps moving day on pace.</code> | TaskActionService — generated/display copy |
| 649 | <code>Final moving-day readiness check</code> | TaskActionService — heading/title |
| 650 | <code>Confirm packing, furniture, building access, a clear path, and your first-night bag.</code> | TaskActionService — generated/display copy |
| 657 | <code>Tap each item as it becomes ready. Nothing here blocks your move.</code> | TaskActionService — generated/display copy |
| 658 | <code>A final readiness record protects the estimate and explains avoidable overages.</code> | TaskActionService — generated/display copy |
| 715 | <code>Your packing supplies kit</code> | TaskActionService — heading/title |
| 724 | <code>The right supplies arrive before packing starts, without a mid-session store run.</code> | TaskActionService — generated/display copy |
| 820 | <code>A signed-in user is required to create a packing plan.</code> | PackingPlanPersistenceError — error message |
| 821 | <code>Add a move date before creating a packing plan.</code> | PackingPlanPersistenceError — generated/display copy |
| 822 | <code>That packing session is no longer available.</code> | PackingPlanPersistenceError — generated/display copy |
| 823 | <code>That packing supplies kit is no longer available.</code> | PackingPlanPersistenceError — generated/display copy |
| 824 | <code>That moving-day readiness check is no longer available.</code> | PackingPlanPersistenceError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/UserState.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 30 | <code>, </code> | UserState — generated/display copy |
| 36 | <code>, </code> | UserState — generated/display copy |

### `Peezy 4.0/MainInterface/Models/WorkflowService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 43 | <code>24-48 hours</code> | WorkflowService — generated/display copy |
| 82 | <code>Invalid response from server</code> | WorkflowServiceError — generated/display copy |
| 84 | <code>Failed to submit answers: \(message)</code> | WorkflowServiceError — generated/display copy |

### `Peezy 4.0/MainInterface/Views/AppRootView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 211 | <code>Loading...</code> | AppLoadingView — screen text |

### `Peezy 4.0/MainInterface/Views/ComparisonCardView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 23 | <code>Price basis</code> | ComparisonCardLabels — generated/display copy |
| 24 | <code>Select this option</code> | ComparisonCardLabels — accessibility copy |
| 32 | <code>Coverage</code> | ComparisonCardLabels — generated/display copy |
| 33 | <code>Open this provider's plan details in the app</code> | ComparisonCardLabels — accessibility copy |
| 86 | <code>\(labels.footerPrefix): \(model.priceBasis)</code> | ComparisonCardView — generated/display copy |
| 88 | <code>, </code> | ComparisonCardView — accessibility copy |
| 127 | <code>\(labels.footerPrefix): \(model.priceBasis)</code> | ComparisonCardView — screen text |
| 160 | <code>•</code> | ComparisonCardView — screen text |
| 165 | <code>•</code> | ComparisonCardView — screen text |

### `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 47 | <code>ASSESSMENT COMPLETE</code> | PaywallGateView — screen text |
| 52 | <code>Let us handle the\nheavy lifting.</code> | PaywallGateView — screen text |
| 58 | <code>Moving costs the average person 25+ hours of stress. Upgrade to Peezy+ and get:</code> | PaywallGateView — screen text |
| 67 | <code>Personalized moving plan built from your assessment</code> | PaywallGateView — generated/display copy |
| 68 | <code>Most tasks, done for you. The rest, walked through step-by-step</code> | PaywallGateView — generated/display copy |
| 69 | <code>AI inventory scanner for every room</code> | PaywallGateView — generated/display copy |
| 70 | <code>Daily task stream so nothing slips through the cracks</code> | PaywallGateView — generated/display copy |
| 71 | <code>Priority support via in-app chat</code> | PaywallGateView — generated/display copy |
| 72 | <code>Plan updates as your move evolves</code> | PaywallGateView — generated/display copy |
| 105 | <code>Redeem a code</code> | PaywallGateView — screen text |
| 110 | <code>·</code> | PaywallGateView — screen text |
| 120 | <code>Restore Purchases</code> | PaywallGateView — screen text |
| 129 | <code>Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings &gt; Apple ID &gt; Subscriptions.</code> | PaywallGateView — alert/confirmation |
| 137 | <code>Privacy Policy</code> | PaywallGateView — generated/display copy |
| 139 | <code>·</code> | PaywallGateView — screen text |
| 140 | <code>Terms of Service</code> | PaywallGateView — generated/display copy |
| 174 | <code>Processing...</code> | PaywallGateView — generated/display copy |
| 185 | <code>Start \(days)-Day Free Trial</code> | PaywallGateView — generated/display copy |
| 189 | <code>Subscribe Yearly</code> | PaywallGateView — generated/display copy |
| 189 | <code>Subscribe for \(price)/yr</code> | PaywallGateView — generated/display copy |
| 193 | <code>Subscribe Weekly</code> | PaywallGateView — generated/display copy |
| 193 | <code>Subscribe for \(price)/wk</code> | PaywallGateView — generated/display copy |
| 219 | <code>—</code> | PaywallGateView — generated/display copy |
| 221 | <code>Weekly</code> | PaywallGateView — heading/title |
| 221 | <code>Yearly</code> | PaywallGateView — heading/title |
| 222 | <code>/ wk</code> | PaywallGateView — generated/display copy |
| 222 | <code>/ yr</code> | PaywallGateView — generated/display copy |
| 224 | <code>BEST VALUE</code> | PaywallGateView — generated/display copy |
| 299 | <code>\(days)-day free trial</code> | PaywallGateView — generated/display copy |
| 301 | <code>Billed yearly</code> | PaywallGateView — generated/display copy |
| 303 | <code>Billed weekly</code> | PaywallGateView — generated/display copy |

### `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 211 | <code>Continue</code> | PeezyHomeView — generated/display copy |
| 211 | <code>Let's do this</code> | PeezyHomeView — generated/display copy |
| 231 | <code>Stay in control.</code> | PeezyHomeView — generated/display copy |
| 232 | <code>We're here to help.</code> | PeezyHomeView — generated/display copy |
| 242 | <code>Just \(daily) \(taskWord) per day to stay on pace.\n\nCheck in once a day, knock them out, and you're set.</code> | PeezyHomeView — generated/display copy |
| 244 | <code>Check in once a day, complete your daily tasks, and you'll be on pace to get everything done.</code> | PeezyHomeView — generated/display copy |
| 247 | <code>Your full task list is in the Tasks tab below.\n\nNeed to update move details? Head to Settings. Questions or feedback? Use the Chat tab.</code> | PeezyHomeView — generated/display copy |
| 249 | <code>Need help with a task? Tap it to learn more, or head to Settings to contact support.</code> | PeezyHomeView — generated/display copy |
| 276 | <code>\(viewModel.dailyTarget) for today</code> | PeezyHomeView — generated/display copy |
| 285 | <code>Get started</code> | PeezyHomeView — generated/display copy |
| 323 | <code>Pick up where I left off</code> | PeezyHomeView — generated/display copy |
| 340 | <code>\(min(viewModel.doseCompletedToday + 1, viewModel.dailyTarget)) of \(viewModel.dailyTarget)</code> | PeezyHomeView — generated/display copy |
| 348 | <code>Loading your task...</code> | PeezyHomeView — screen text |
| 389 | <code>Keep going?</code> | PeezyHomeView — button/action label |
| 389 | <code>Want to get ahead?</code> | PeezyHomeView — button/action label |

### `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 150 | <code>Home</code> | PeezyTab — generated/display copy |
| 151 | <code>Tasks</code> | PeezyTab — generated/display copy |
| 152 | <code>Chat</code> | PeezyTab — generated/display copy |
| 153 | <code>Settings</code> | PeezyTab — generated/display copy |
| 199 | <code>Switches to \(tab.label) tab</code> | PeezyFloatingTabBar — accessibility copy |

### `Peezy 4.0/MainInterface/Views/ProviderActionCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 32 | <code>address change</code> | ProviderActionKind — generated/display copy |
| 34 | <code>location transfer</code> | ProviderActionKind — generated/display copy |
| 35 | <code>records transfer</code> | ProviderActionKind — generated/display copy |
| 36 | <code>account closure</code> | ProviderActionKind — generated/display copy |
| 43 | <code>Hi, I'm calling to update the address on my account to my new address.</code> | ProviderActionKind — generated/display copy |
| 45 | <code>Hi, I'm calling to cancel my membership. Please confirm the effective date and any final charge.</code> | ProviderActionKind — generated/display copy |
| 47 | <code>Hi, I'm calling to transfer my membership to a location near my new address.</code> | ProviderActionKind — generated/display copy |
| 49 | <code>Hi, I'm calling to transfer my records to a new provider. What do you need from me?</code> | ProviderActionKind — generated/display copy |
| 51 | <code>Hi, I'm calling to close my account. Please confirm the effective date and any final balance.</code> | ProviderActionKind — generated/display copy |
| 115 | <code>Copied your details.</code> | ProviderActionCard — generated/display copy |
| 118 | <code>Copy my details</code> | ProviderActionCard — option/list label |
| 125 | <code>Copies your name, new address, and phone number when available</code> | ProviderActionCard — accessibility copy |
| 129 | <code>Add your name and new address in Settings to copy them here.</code> | ProviderActionCard — screen text |
| 145 | <code>Done</code> | ProviderActionCard — generated/display copy |
| 166 | <code>•</code> | ProviderActionCard — screen text |
| 208 | <code>Back to provider search</code> | ProviderActionCard — accessibility copy |
| 230 | <code>Open </code> | ProviderActionCard — generated/display copy |
| 234 | <code> page in the app</code> | ProviderActionCard — generated/display copy |
| 234 | <code>'s official </code> | ProviderActionCard — generated/display copy |
| 234 | <code>Opens </code> | ProviderActionCard — generated/display copy |
| 251 | <code>Suggested call script: \(actionKind.callScript)</code> | ProviderActionCard — accessibility copy |
| 254 | <code>Call </code> | ProviderActionCard — generated/display copy |
| 260 | <code>Calls </code> | ProviderActionCard — accessibility copy |
| 271 | <code>Continue with \(resolution.name)</code> | ProviderActionCard — generated/display copy |
| 272 | <code>Call \(resolution.name)</code> | ProviderActionCard — generated/display copy |
| 273 | <code>We'll take it from here</code> | ProviderActionCard — generated/display copy |
| 295 | <code>Name: \(name)</code> | ProviderActionCard — generated/display copy |
| 298 | <code>New address: \(address)</code> | ProviderActionCard — generated/display copy |
| 302 | <code>Phone: \(phone)</code> | ProviderActionCard — generated/display copy |
| 304 | <code>\n</code> | ProviderActionCard — generated/display copy |
| 326 | <code>Cancel provider lookup</code> | ProviderResolutionLoadingCard — accessibility copy |
| 342 | <code>Checking \(providerName)…</code> | ProviderResolutionLoadingCard — generated/display copy |
| 345 | <code> for an official action</code> | ProviderResolutionLoadingCard — accessibility copy |
| 345 | <code>Checking </code> | ProviderResolutionLoadingCard — accessibility copy |

### `Peezy 4.0/MainInterface/Views/Shared/HomeBackgroundComponents.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>Loading your tasks...</code> | LoadingView — screen text |
| 52 | <code>Dismiss</code> | ErrorToast — button/action label |

### `Peezy 4.0/MainInterface/Views/Shared/PeezyWordmark.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>peezy</code> | PeezyWordmark — screen text |

### `Peezy 4.0/MainInterface/Views/SupportChatView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 46 | <code>Support</code> | SupportChatView — screen text |
| 50 | <code>We typically respond within a few hours</code> | SupportChatView — screen text |
| 68 | <code>Ask about your tasks, your move, or anything we can help with. We usually respond within a few hours.</code> | SupportChatView — screen text |
| 152 | <code>What can we help with?</code> | SupportChatView — field placeholder/helper |
| 220 | <code>Yesterday</code> | SupportChatView — generated/display copy |

### `Peezy 4.0/Menu/PeezySettingsView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 157 | <code>Move date updated</code> | PeezySettingsView — generated/display copy |
| 161 | <code>Current Address</code> | PeezySettingsView — heading/title |
| 164 | <code>Current address updated</code> | PeezySettingsView — generated/display copy |
| 168 | <code>New Address</code> | PeezySettingsView — heading/title |
| 171 | <code>New address updated</code> | PeezySettingsView — generated/display copy |
| 177 | <code>Profile updated</code> | PeezySettingsView — generated/display copy |
| 180 | <code>Retake Assessment?</code> | PeezySettingsView — alert/confirmation |
| 181 | <code>Cancel</code> | PeezySettingsView — button/action label |
| 182 | <code>Retake</code> | PeezySettingsView — button/action label |
| 186 | <code>This will reset your tasks and personalized plan. Your account will not be affected.</code> | PeezySettingsView — alert/confirmation |
| 188 | <code>Sign Out?</code> | PeezySettingsView — alert/confirmation |
| 189 | <code>Cancel</code> | PeezySettingsView — button/action label |
| 190 | <code>Sign Out</code> | PeezySettingsView — button/action label |
| 194 | <code>You'll need to sign back in to access your tasks.</code> | PeezySettingsView — alert/confirmation |
| 196 | <code>Delete Account?</code> | PeezySettingsView — alert/confirmation |
| 197 | <code>Cancel</code> | PeezySettingsView — button/action label |
| 198 | <code>Delete Everything</code> | PeezySettingsView — button/action label |
| 202 | <code>This will permanently delete your account, all your tasks, and all your data. This cannot be undone.\n\nIf you have an active subscription, please cancel it first in your Apple ID settings.</code> | PeezySettingsView — error message |
| 204 | <code>Account deletion failed</code> | PeezySettingsView — error message |
| 205 | <code>OK</code> | PeezySettingsView — button/action label |
| 209 | <code>Restore purchases</code> | PeezySettingsView — error message |
| 213 | <code>OK</code> | PeezySettingsView — button/action label |
| 226 | <code>Settings</code> | PeezySettingsView — screen text |
| 253 | <code>Peezy User</code> | PeezySettingsView — screen text |
| 282 | <code>Edit Move Details</code> | PeezySettingsView — generated/display copy |
| 288 | <code>Move Date</code> | PeezySettingsView — generated/display copy |
| 301 | <code>Current Address</code> | PeezySettingsView — generated/display copy |
| 302 | <code>Not set</code> | PeezySettingsView — generated/display copy |
| 314 | <code>New Address</code> | PeezySettingsView — generated/display copy |
| 315 | <code>Not set</code> | PeezySettingsView — generated/display copy |
| 325 | <code>Retake Assessment</code> | PeezySettingsView — alert/confirmation |
| 338 | <code>Subscription</code> | PeezySettingsView — generated/display copy |
| 369 | <code>Manage Subscription</code> | PeezySettingsView — generated/display copy |
| 378 | <code>Restore purchases</code> | PeezySettingsView — generated/display copy |
| 382 | <code>Purchases restored successfully.</code> | PeezySettingsView — error message |
| 384 | <code>Unable to restore purchases. Please try again.</code> | PeezySettingsView — generated/display copy |
| 397 | <code>Free Trial Active</code> | PeezySettingsView — generated/display copy |
| 399 | <code>Peezy Premium</code> | PeezySettingsView — generated/display copy |
| 401 | <code>Subscription Expired</code> | PeezySettingsView — generated/display copy |
| 403 | <code>Subscription Revoked</code> | PeezySettingsView — generated/display copy |
| 405 | <code>Not Subscribed</code> | PeezySettingsView — generated/display copy |
| 414 | <code>\(planName) plan — trial ends in \(daysLeft) day\(daysLeft == 1 ? "" : "s")</code> | PeezySettingsView — generated/display copy |
| 417 | <code>\(planName) plan — renews \(formattedDate(expires))</code> | PeezySettingsView — generated/display copy |
| 419 | <code>Resubscribe to access all features</code> | PeezySettingsView — generated/display copy |
| 429 | <code>Subscription</code> | PeezySettingsView — generated/display copy |
| 434 | <code>Subscription</code> | PeezySettingsView — generated/display copy |
| 436 | <code>Weekly</code> | PeezySettingsView — generated/display copy |
| 438 | <code>Monthly</code> | PeezySettingsView — generated/display copy |
| 440 | <code>Yearly</code> | PeezySettingsView — generated/display copy |
| 442 | <code>Subscription</code> | PeezySettingsView — generated/display copy |
| 450 | <code>Inventory</code> | PeezySettingsView — generated/display copy |
| 453 | <code>Scan Room Inventory</code> | PeezySettingsView — generated/display copy |
| 466 | <code>Support</code> | PeezySettingsView — generated/display copy |
| 469 | <code>Contact Support</code> | PeezySettingsView — generated/display copy |
| 475 | <code>Privacy Policy</code> | PeezySettingsView — generated/display copy |
| 482 | <code>Terms of Service</code> | PeezySettingsView — generated/display copy |
| 498 | <code>Sign Out</code> | PeezySettingsView — generated/display copy |
| 509 | <code>Delete account</code> | PeezySettingsView — generated/display copy |
| 524 | <code>Peezy</code> | PeezySettingsView — screen text |
| 528 | <code>Version \(appVersion)</code> | PeezySettingsView — screen text |
| 637 | <code>Resetting your data...</code> | PeezySettingsView — generated/display copy |
| 673 | <code>Failed to reset: \(error.localizedDescription)</code> | PeezySettingsView — error message |
| 683 | <code>Deleting your account...</code> | PeezySettingsView — generated/display copy |
| 705 | <code>Account deletion failed. Please try again or contact support.</code> | PeezySettingsView — error message |
| 715 | <code>P</code> | PeezySettingsView — generated/display copy |
| 718 | <code>\(parts[0].prefix(1))\(parts[1].prefix(1))</code> | PeezySettingsView — generated/display copy |
| 724 | <code>1.0</code> | PeezySettingsView — generated/display copy |
| 746 | <code>...</code> | PeezySettingsView — generated/display copy |
| 810 | <code>Failed to save: \(error.localizedDescription)</code> | EditedAddressKind — error message |
| 844 | <code>Failed to save: \(error.localizedDescription)</code> | EditedAddressKind — error message |
| 874 | <code>Move Date</code> | EditMoveDateSheet — generated/display copy |
| 886 | <code>Move Date</code> | EditMoveDateSheet — heading/title |
| 890 | <code>Cancel</code> | EditMoveDateSheet — button/action label |
| 895 | <code>Update</code> | EditMoveDateSheet — button/action label |
| 904 | <code>Update Move Date?</code> | EditMoveDateSheet — alert/confirmation |
| 905 | <code>Cancel</code> | EditMoveDateSheet — button/action label |
| 906 | <code>Update</code> | EditMoveDateSheet — button/action label |
| 911 | <code>This will update your tasks and timeline to reflect the new date.</code> | EditMoveDateSheet — screen text |
| 952 | <code>Enter address</code> | EditAddressSheet — field placeholder/helper |
| 1026 | <code>Save</code> | EditAddressSheet — generated/display copy |
| 1043 | <code>Cancel</code> | EditAddressSheet — button/action label |
| 1078 | <code>Name</code> | EditNameEmailSheet — generated/display copy |
| 1079 | <code>Your name</code> | EditNameEmailSheet — field placeholder/helper |
| 1083 | <code>Email</code> | EditNameEmailSheet — generated/display copy |
| 1084 | <code>Email address</code> | EditNameEmailSheet — field placeholder/helper |
| 1097 | <code>Save Changes</code> | EditNameEmailSheet — generated/display copy |
| 1097 | <code>Saving...</code> | EditNameEmailSheet — generated/display copy |
| 1106 | <code>Edit Profile</code> | EditNameEmailSheet — heading/title |
| 1110 | <code>Cancel</code> | EditNameEmailSheet — button/action label |
| 1149 | <code>Not signed in</code> | EditNameEmailSheet — error message |
| 1181 | <code>Save failed: \(error.localizedDescription)</code> | EditNameEmailSheet — error message |

### `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 161 | <code>Good to Know</code> | FlowEngineView — heading/title |
| 163 | <code>Got it</code> | FlowEngineView — button/action label |
| 172 | <code>Would you like us to take care of this for you?</code> | FlowEngineView — generated/display copy |
| 177 | <code>~1 hr</code> | FlowEngineView — generated/display copy |
| 228 | <code>Search...</code> | FlowEngineView — field placeholder/helper |
| 256 | <code>Is this your move date?</code> | FlowEngineView — generated/display copy |
| 304 | <code> and </code> | FlowEngineView — generated/display copy |
| 635 | <code>Coming right up</code> | ComingRightUpCard — screen text |
| 640 | <code>This one isn't quite ready in the app — we're on it. It'll stay on your list.</code> | ComingRightUpCard — screen text |
| 651 | <code>Got it</code> | ComingRightUpCard — generated/display copy |

### `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 19 | <code>This task is missing the identity required to save progress.</code> | FlowProgressPersistenceError — error message |
| 120 | <code>Missing user or task identity</code> | FlowExitCoordinator — error message |
| 257 | <code>Close task</code> | OutermostTaskFlowContainer — accessibility copy |

### `Peezy 4.0/Tasks/FlowEngine/InAppTaskFlows.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 81 | <code>Saving...</code> | InAppFlowSaving — screen text |
| 113 | <code>Add your new address</code> | AddNewAddressFlow — heading/title |
| 115 | <code>Add address</code> | AddNewAddressFlow — button/action label |
| 126 | <code>New Address</code> | AddNewAddressFlow — heading/title |
| 174 | <code>Couldn't save the address — please try again</code> | AddNewAddressFlow — error message |
| 204 | <code>Lock in your move date</code> | ConfirmMoveDateFlow — heading/title |
| 205 | <code>Is this the real date?</code> | ConfirmMoveDateFlow — generated/display copy |
| 207 | <code>Lock it in</code> | ConfirmMoveDateFlow — generated/display copy |
| 246 | <code>Couldn't save the date — please try again</code> | ConfirmMoveDateFlow — error message |
| 275 | <code>Lighten the load?</code> | DeclutterIntentFlow — option/list label |
| 276 | <code>Lightening the load before the move?</code> | DeclutterIntentFlow — option/list label |
| 278 | <code>Yes — I'll sell some of it</code> | DeclutterIntentFlow — option/list label |
| 279 | <code>Yes — donate or junk it</code> | DeclutterIntentFlow — option/list label |
| 280 | <code>Not this move</code> | DeclutterIntentFlow — generated/display copy |
| 319 | <code>Couldn't save — please try again</code> | DeclutterIntentFlow — error message |
| 348 | <code>Need a storage unit?</code> | StorageNeedFlow — option/list label |
| 349 | <code>Will everything fit — or might you need a unit?</code> | StorageNeedFlow — option/list label |
| 351 | <code>I'll need a unit</code> | StorageNeedFlow — option/list label |
| 352 | <code>It all fits</code> | StorageNeedFlow — option/list label |
| 388 | <code>Couldn't save — please try again</code> | StorageNeedFlow — error message |

### `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 46 | <code>Untitled Task</code> | PeezyCardFirestoreMapper — heading/title |

### `Peezy 4.0/Tasks/Store/TasksStore.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 88 | <code>Couldn't mark complete</code> | LoadState — error message |
| 104 | <code>\(card.title) moved back to active</code> | LoadState — error message |
| 107 | <code>Couldn't undo — please try again</code> | LoadState — error message |
| 164 | <code>Inventory reset — ready to scan again</code> | LoadState — generated/display copy |
| 174 | <code>Inventory reset needs a connection</code> | LoadState — error message |
| 176 | <code>Couldn't reset inventory — please try again</code> | LoadState — error message |

### `Peezy 4.0/Tasks/Task Card Components/AdminMemoFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 32 | <code>Update from Peezy</code> | AdminMemoFlow — heading/title |
| 47 | <code>Loading...</code> | AdminMemoFlow — screen text |
| 144 | <code>Got it</code> | AdminMemoFlow — generated/display copy |
| 156 | <code>No memo to display</code> | AdminMemoFlow — error message |
| 170 | <code>Memo not found</code> | AdminMemoFlow — error message |
| 176 | <code>Update from Peezy</code> | AdminMemoFlow — heading/title |
| 181 | <code>No content in this memo</code> | AdminMemoFlow — error message |
| 188 | <code>Failed to load memo</code> | AdminMemoFlow — error message |

### `Peezy 4.0/Tasks/Task Card Components/QuoteSelectionFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 35 | <code>Your quotes are ready</code> | QuoteSelectionFlow — heading/title |
| 52 | <code>Loading quotes...</code> | QuoteSelectionFlow — screen text |
| 132 | <code>Pick the one that\nworks for you</code> | QuoteSelectionFlow — screen text |
| 142 | <code>Tap an option to select it. You can always change your mind.</code> | QuoteSelectionFlow — screen text |
| 182 | <code>Recommended</code> | QuoteSelectionFlow — screen text |
| 248 | <code>Great choice</code> | QuoteSelectionFlow — screen text |
| 276 | <code>We'll reach out to them and get everything set up for you.</code> | QuoteSelectionFlow — screen text |
| 286 | <code>Confirm Selection</code> | QuoteSelectionFlow — generated/display copy |
| 286 | <code>Submitting...</code> | QuoteSelectionFlow — generated/display copy |
| 300 | <code>No task ID provided</code> | QuoteSelectionFlow — error message |
| 314 | <code>Quote not found</code> | QuoteSelectionFlow — error message |
| 320 | <code>Your quotes are ready</code> | QuoteSelectionFlow — heading/title |
| 340 | <code>No quote options found</code> | QuoteSelectionFlow — error message |
| 351 | <code>Failed to load quotes</code> | QuoteSelectionFlow — error message |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowBusinessSearchCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 89 | <code>Search...</code> | TaskFlowBusinessSearchCard — field placeholder/helper |
| 92 | <code>Continue</code> | TaskFlowBusinessSearchCard — generated/display copy |
| 274 | <code>\(result.title), \(result.subtitle)</code> | TaskFlowBusinessSearchCard — accessibility copy |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowConfirmAddressCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 31 | <code>That's right</code> | TaskFlowConfirmAddressCard — generated/display copy |
| 32 | <code>Update this</code> | TaskFlowConfirmAddressCard — generated/display copy |
| 154 | <code>Update address</code> | TaskFlowConfirmAddressCard — screen text |
| 183 | <code>Cancel</code> | TaskFlowConfirmAddressCard — screen text |
| 206 | <code>Save</code> | TaskFlowConfirmAddressCard — screen text |
| 237 | <code>Search address...</code> | TaskFlowConfirmAddressCard — field placeholder/helper |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowConfirmDateCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 29 | <code>That's right</code> | TaskFlowConfirmDateCard — generated/display copy |
| 30 | <code>Update this</code> | TaskFlowConfirmDateCard — generated/display copy |
| 150 | <code>Select date</code> | TaskFlowConfirmDateCard — generated/display copy |
| 175 | <code>Cancel</code> | TaskFlowConfirmDateCard — screen text |
| 194 | <code>Save</code> | TaskFlowConfirmDateCard — screen text |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowDecisionCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 17 | <code>Would you like us to take care of this for you?</code> | TaskFlowDecisionCard — generated/display copy |
| 19 | <code>Yes</code> | TaskFlowDecisionCard — generated/display copy |
| 20 | <code>No, I got it</code> | TaskFlowDecisionCard — generated/display copy |
| 23 | <code>~1 hr</code> | TaskFlowDecisionCard — generated/display copy |
| 69 | <code>\(yesLabel) · </code> | TaskFlowDecisionCard — screen text |
| 72 | <code>Saves \(timeSaved)</code> | TaskFlowDecisionCard — screen text |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowInfoCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 18 | <code>Continue</code> | TaskFlowInfoCard — button/action label |
| 61 | <code> </code> | TaskFlowInfoCard — screen text |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowStatusCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>What's the plan with this?</code> | TaskFlowStatusCard — generated/display copy |
| 31 | <code>Later</code> | TaskFlowStatusCard — option/list label |
| 32 | <code>Mark as in progress</code> | TaskFlowStatusCard — option/list label |
| 33 | <code>Already done</code> | TaskFlowStatusCard — generated/display copy |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowSummaryCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>Done</code> | TaskFlowSummaryCard — button/action label |
| 43 | <code>Eezy Peezy!</code> | TaskFlowSummaryCard — screen text |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowTilesCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 69 | <code>Continue</code> | TaskFlowTilesCard — generated/display copy |
| 69 | <code>None</code> | TaskFlowTilesCard — generated/display copy |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>Continue</code> | TaskFlowTitleCard — button/action label |
| 24 | <code> </code> | TaskFlowTitleCard — heading/title |
| 25 | <code> </code> | TaskFlowTitleCard — heading/title |
| 83 | <code>Later</code> | TaskFlowTitleCard — screen text |
| 98 | <code>Tap continue to start</code> | TaskFlowTitleCard — accessibility copy |

### `Peezy 4.0/Tasks/Task Cards/BoxReturnView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 94 | <code>Finding your packing kit…</code> | BoxReturnQuestion — error message |
| 103 | <code>Box return</code> | BoxReturnQuestion — heading/title |
| 109 | <code>Question \(questionIndex + 1) of \(boxReturnQuestions.count)</code> | BoxReturnQuestion — screen text |
| 132 | <code>Save box count</code> | BoxReturnQuestion — generated/display copy |
| 132 | <code>Saving…</code> | BoxReturnQuestion — generated/display copy |
| 133 | <code>Continue</code> | BoxReturnQuestion — generated/display copy |
| 139 | <code>Close</code> | BoxReturnQuestion — button/action label |
| 156 | <code>How many boxes are you returning or recycling?</code> | BoxReturnQuestion — screen text |
| 161 | <code>Your kit included \(delivered) boxes. The count helps us size future kits with less waste.</code> | BoxReturnQuestion — screen text |
| 168 | <code>Boxes</code> | BoxReturnQuestion — screen text |
| 171 | <code>\(returnedCount)</code> | BoxReturnQuestion — screen text |
| 180 | <code>Boxes returning or recycling</code> | BoxReturnQuestion — accessibility copy |
| 181 | <code>\(returnedCount)</code> | BoxReturnQuestion — accessibility copy |
| 185 | <code>Did you run out of boxes before move day?</code> | BoxReturnQuestion — screen text |
| 191 | <code>Yes</code> | BoxReturnQuestion — generated/display copy |
| 192 | <code>No</code> | BoxReturnQuestion — generated/display copy |
| 196 | <code>Would you like Peezy to arrange pickup?</code> | BoxReturnQuestion — screen text |
| 202 | <code>Yes</code> | BoxReturnQuestion — generated/display copy |
| 203 | <code>No</code> | BoxReturnQuestion — generated/display copy |
| 207 | <code>We'll send the count to the concierge team and follow up about pickup.</code> | BoxReturnQuestion — screen text |
| 226 | <code>Box return</code> | BoxReturnQuestion — heading/title |
| 233 | <code>Got it — \(calibration.returned) of \(calibration.delivered) boxes recorded.</code> | BoxReturnQuestion — screen text |
| 239 | <code>Your pickup request is with the concierge team.</code> | BoxReturnQuestion — screen text |
| 248 | <code>Done</code> | BoxReturnQuestion — generated/display copy |
| 260 | <code>Box return</code> | BoxReturnQuestion — error message |
| 263 | <code>Couldn't load your kit</code> | BoxReturnQuestion — option/list label |
| 270 | <code>Try again</code> | BoxReturnQuestion — generated/display copy |
| 274 | <code>Close</code> | BoxReturnQuestion — button/action label |
| 340 | <code>Not selected</code> | BoxReturnQuestion — accessibility copy |
| 340 | <code>Selected</code> | BoxReturnQuestion — accessibility copy |
| 365 | <code>Not selected</code> | BoxReturnQuestion — accessibility copy |
| 365 | <code>Selected</code> | BoxReturnQuestion — accessibility copy |

### `Peezy 4.0/Tasks/Task Cards/FindCleanersFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 25 | <code>Find my cleaners</code> | FindCleanersFlow — heading/title |
| 120 | <code>Which place needs cleaning?</code> | FindCleanersFlow — generated/display copy |
| 121 | <code>Old place — move-out clean</code> | FindCleanersFlow — generated/display copy |
| 122 | <code>New place — move-in clean</code> | FindCleanersFlow — generated/display copy |
| 123 | <code>Both places</code> | FindCleanersFlow — generated/display copy |
| 134 | <code>What services do you need?</code> | FindCleanersFlow — generated/display copy |
| 135 | <code>Standard clean</code> | FindCleanersFlow — generated/display copy |
| 136 | <code>Deep clean</code> | FindCleanersFlow — generated/display copy |
| 137 | <code>Carpet cleaning</code> | FindCleanersFlow — generated/display copy |
| 138 | <code>Window cleaning</code> | FindCleanersFlow — generated/display copy |
| 150 | <code>When do you need the move-out clean?</code> | FindCleanersFlow — generated/display copy |
| 151 | <code>Morning</code> | FindCleanersFlow — generated/display copy |
| 152 | <code>Afternoon</code> | FindCleanersFlow — generated/display copy |
| 153 | <code>Evening</code> | FindCleanersFlow — generated/display copy |
| 154 | <code>Flexible</code> | FindCleanersFlow — generated/display copy |
| 165 | <code>When do you need the move-in clean?</code> | FindCleanersFlow — generated/display copy |
| 166 | <code>Morning</code> | FindCleanersFlow — generated/display copy |
| 167 | <code>Afternoon</code> | FindCleanersFlow — generated/display copy |
| 168 | <code>Evening</code> | FindCleanersFlow — generated/display copy |
| 169 | <code>Flexible</code> | FindCleanersFlow — generated/display copy |
| 180 | <code>We'll find cleaners who can handle everything you selected and get you quotes.</code> | FindCleanersFlow — generated/display copy |
| 181 | <code>Response times are typically 24–48 hours.</code> | FindCleanersFlow — helper/subtext |

### `Peezy 4.0/Tasks/Task Cards/FindMoversFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 81 | <code>Preparing your move scope…</code> | FindMoversFlow — generated/display copy |
| 142 | <code>your selected company</code> | FindMoversFlow — alert/confirmation |
| 149 | <code>An unexpected error occurred.</code> | FindMoversFlow — error message |
| 182 | <code>Your quote request is in</code> | FindMoversFlow — screen text |
| 186 | <code>We'll follow up with your hand-built mover quote within a day.</code> | FindMoversFlow — screen text |
| 189 | <code>Done</code> | FindMoversFlow — generated/display copy |
| 219 | <code>Request a mover quote</code> | MoversConciergeQuoteCard — heading/title |
| 241 | <code>Anything we should know?</code> | MoversConciergeQuoteCard — field placeholder/helper |
| 256 | <code>Request my quote</code> | MoversConciergeQuoteCard — generated/display copy |
| 256 | <code>Sending…</code> | MoversConciergeQuoteCard — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/HandleAutoInsuranceFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 24 | <code>Handle my auto insurance</code> | HandleAutoInsuranceFlow — heading/title |
| 98 | <code>We'll reach out to \(providerName) about switching your policy to cover your new place.</code> | HandleAutoInsuranceFlow — option/list label |
| 100 | <code>We'll get you 3 options — one from \(providerName) and two of the best alternatives.</code> | HandleAutoInsuranceFlow — option/list label |
| 105 | <code>your provider</code> | HandleAutoInsuranceFlow — generated/display copy |
| 196 | <code>Do you currently have auto insurance?</code> | HandleAutoInsuranceFlow — option/list label |
| 198 | <code>Yes</code> | HandleAutoInsuranceFlow — option/list label |
| 199 | <code>No</code> | HandleAutoInsuranceFlow — option/list label |
| 211 | <code>How would you like to handle this?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 212 | <code>I'd like help</code> | HandleAutoInsuranceFlow — generated/display copy |
| 213 | <code>I have an agent</code> | HandleAutoInsuranceFlow — generated/display copy |
| 224 | <code>What would you like to do?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 225 | <code>Update my address</code> | HandleAutoInsuranceFlow — generated/display copy |
| 226 | <code>Switch to a new policy</code> | HandleAutoInsuranceFlow — generated/display copy |
| 258 | <code>Who's your current provider?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 259 | <code>Search for an insurance company...</code> | HandleAutoInsuranceFlow — field placeholder/helper |
| 272 | <code>We'll reach out to \(providerName) and get your address updated.</code> | HandleAutoInsuranceFlow — generated/display copy |
| 273 | <code>Response times are typically 24–48 hours.</code> | HandleAutoInsuranceFlow — helper/subtext |
| 287 | <code>Who do you have it with now?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 288 | <code>Search for an insurance company...</code> | HandleAutoInsuranceFlow — field placeholder/helper |
| 303 | <code>Would you like to stay with \(providerName), or get quotes from others too?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 304 | <code>Keep my current provider</code> | HandleAutoInsuranceFlow — generated/display copy |
| 305 | <code>Get quotes from others too</code> | HandleAutoInsuranceFlow — generated/display copy |
| 317 | <code>Response times are typically 24–48 hours.</code> | HandleAutoInsuranceFlow — helper/subtext |
| 331 | <code>Good to Know</code> | HandleAutoInsuranceFlow — heading/title |
| 332 | <code>Most states require auto insurance to legally drive. If you're getting a car at your new place, you'll need a policy before registration.</code> | HandleAutoInsuranceFlow — generated/display copy |
| 333 | <code>Got it</code> | HandleAutoInsuranceFlow — button/action label |
| 358 | <code>Good to Know</code> | HandleAutoInsuranceFlow — heading/title |
| 359 | <code>Here's what to tell your agent: your new address, your move date, and whether your housing type is changing. Ask them to confirm your new rate before the move — rates change by zip code.</code> | HandleAutoInsuranceFlow — generated/display copy |
| 360 | <code>Got it</code> | HandleAutoInsuranceFlow — button/action label |

### `Peezy 4.0/Tasks/Task Cards/HandleHomeInsuranceFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 23 | <code>Handle my home insurance</code> | HandleHomeInsuranceFlow — heading/title |
| 97 | <code>We'll reach out to \(providerName) about switching your policy to cover your new place.</code> | HandleHomeInsuranceFlow — option/list label |
| 99 | <code>We'll get you 3 options — one from \(providerName) and two of the best alternatives.</code> | HandleHomeInsuranceFlow — option/list label |
| 104 | <code>your provider</code> | HandleHomeInsuranceFlow — generated/display copy |
| 195 | <code>Do you currently have home insurance?</code> | HandleHomeInsuranceFlow — option/list label |
| 197 | <code>Yes</code> | HandleHomeInsuranceFlow — option/list label |
| 198 | <code>No</code> | HandleHomeInsuranceFlow — option/list label |
| 210 | <code>How would you like to handle this?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 211 | <code>I'd like help</code> | HandleHomeInsuranceFlow — generated/display copy |
| 212 | <code>I have an agent</code> | HandleHomeInsuranceFlow — generated/display copy |
| 223 | <code>What would you like to do?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 224 | <code>Update my address</code> | HandleHomeInsuranceFlow — generated/display copy |
| 225 | <code>Switch to a new policy</code> | HandleHomeInsuranceFlow — generated/display copy |
| 257 | <code>Who's your current provider?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 258 | <code>Search for an insurance company...</code> | HandleHomeInsuranceFlow — field placeholder/helper |
| 271 | <code>We'll reach out to \(providerName) and get your address updated.</code> | HandleHomeInsuranceFlow — generated/display copy |
| 272 | <code>Response times are typically 24–48 hours.</code> | HandleHomeInsuranceFlow — helper/subtext |
| 286 | <code>Who do you have it with now?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 287 | <code>Search for an insurance company...</code> | HandleHomeInsuranceFlow — field placeholder/helper |
| 302 | <code>Would you like to stay with \(providerName), or get quotes from others too?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 303 | <code>Keep my current provider</code> | HandleHomeInsuranceFlow — generated/display copy |
| 304 | <code>Get quotes from others too</code> | HandleHomeInsuranceFlow — generated/display copy |
| 316 | <code>Response times are typically 24–48 hours.</code> | HandleHomeInsuranceFlow — helper/subtext |
| 330 | <code>Good to Know</code> | HandleHomeInsuranceFlow — heading/title |
| 331 | <code>If you're renting, most leases require renter's insurance — it's usually $15-25/month and protects your stuff. If you're buying, your lender requires homeowner's insurance before closing.</code> | HandleHomeInsuranceFlow — generated/display copy |
| 332 | <code>Got it</code> | HandleHomeInsuranceFlow — button/action label |
| 357 | <code>Good to Know</code> | HandleHomeInsuranceFlow — heading/title |
| 358 | <code>Here's what to tell your agent: your new address, your move date, and whether your housing type is changing. Ask them to confirm your new rate before the move — rates change by zip code.</code> | HandleHomeInsuranceFlow — generated/display copy |
| 359 | <code>Got it</code> | HandleHomeInsuranceFlow — button/action label |

### `Peezy 4.0/Tasks/Task Cards/MoveCheckInView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 131 | <code>Loading your moving-day check-in…</code> | CheckInQuestion — error message |
| 140 | <code>Moving-day check-in</code> | CheckInQuestion — heading/title |
| 146 | <code>Question \(questionIndex + 1) of \(checkInQuestions.count)</code> | CheckInQuestion — screen text |
| 163 | <code>Saving…</code> | CheckInQuestion — generated/display copy |
| 163 | <code>Submit check-in</code> | CheckInQuestion — generated/display copy |
| 164 | <code>Continue</code> | CheckInQuestion — generated/display copy |
| 171 | <code>Close</code> | CheckInQuestion — button/action label |
| 191 | <code>Did they arrive in the window?</code> | CheckInQuestion — generated/display copy |
| 200 | <code>Did the crew work steadily?</code> | CheckInQuestion — generated/display copy |
| 209 | <code>Did anything cost more than quoted?</code> | CheckInQuestion — generated/display copy |
| 218 | <code>Was anything damaged?</code> | CheckInQuestion — generated/display copy |
| 227 | <code>Anything else we should know?</code> | CheckInQuestion — screen text |
| 231 | <code>Optional note</code> | CheckInQuestion — field placeholder/helper |
| 238 | <code>What was the final bill?</code> | CheckInQuestion — screen text |
| 244 | <code>Peezy estimate: \(money(bookingContext.estimatedRange.low))–\(money(bookingContext.estimatedRange.high))</code> | CheckInQuestion — generated/display copy |
| 250 | <code>Final bill (optional)</code> | CheckInQuestion — field placeholder/helper |
| 255 | <code>Enter a final bill greater than $0, or leave it blank.</code> | CheckInQuestion — screen text |
| 281 | <code>Moving-day check-in</code> | CheckInQuestion — heading/title |
| 288 | <code>Thanks. We saved the facts and we'll follow up on anything that needs attention.</code> | CheckInQuestion — screen text |
| 297 | <code>Done</code> | CheckInQuestion — generated/display copy |
| 309 | <code>Moving-day check-in</code> | CheckInQuestion — error message |
| 312 | <code>Couldn't load your check-in</code> | CheckInQuestion — option/list label |
| 319 | <code>Try again</code> | CheckInQuestion — generated/display copy |
| 323 | <code>Close</code> | CheckInQuestion — button/action label |
| 347 | <code>Yes</code> | CheckInQuestion — generated/display copy |
| 348 | <code>No</code> | CheckInQuestion — generated/display copy |
| 384 | <code>Not selected</code> | CheckInQuestion — accessibility copy |
| 384 | <code>Selected</code> | CheckInQuestion — accessibility copy |

### `Peezy 4.0/Tasks/Task Cards/MoveRefinementView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>1 Bedroom</code> | MoveRefinementView — generated/display copy |
| 15 | <code>2 Bedrooms</code> | MoveRefinementView — generated/display copy |
| 15 | <code>3 Bedrooms</code> | MoveRefinementView — generated/display copy |
| 15 | <code>4 Bedrooms</code> | MoveRefinementView — generated/display copy |
| 15 | <code>5 Bedrooms</code> | MoveRefinementView — generated/display copy |
| 15 | <code>6+ Bedrooms</code> | MoveRefinementView — generated/display copy |
| 16 | <code>Elevator</code> | MoveRefinementView — generated/display copy |
| 16 | <code>Ground Floor</code> | MoveRefinementView — generated/display copy |
| 16 | <code>Reserved Elevator</code> | MoveRefinementView — generated/display copy |
| 16 | <code>Stairs</code> | MoveRefinementView — generated/display copy |
| 16 | <code>Unknown</code> | MoveRefinementView — generated/display copy |
| 67 | <code>Book your movers</code> | Question — heading/title |
| 70 | <code>Question \(questionIndex + 1) of \(questions.count)</code> | Question — screen text |
| 91 | <code>Compare prices</code> | Question — generated/display copy |
| 91 | <code>Continue</code> | Question — generated/display copy |
| 104 | <code>How many bedrooms are in your current home?</code> | Question — generated/display copy |
| 105 | <code>How many bedrooms are in your destination home?</code> | Question — generated/display copy |
| 106 | <code>Are you moving anything from storage?</code> | Question — generated/display copy |
| 107 | <code>How large is the storage unit?</code> | Question — generated/display copy |
| 108 | <code>How full is the storage unit?</code> | Question — generated/display copy |
| 109 | <code>Is the storage unit a stop on moving day?</code> | Question — generated/display copy |
| 110 | <code>Where is the storage unit?</code> | Question — generated/display copy |
| 111 | <code>What's the access like at your current home?</code> | Question — generated/display copy |
| 112 | <code>Is there a long carry at your current home?</code> | Question — generated/display copy |
| 113 | <code>What's the access like at your destination?</code> | Question — generated/display copy |
| 114 | <code>Is there a long carry at your destination?</code> | Question — generated/display copy |
| 115 | <code>How packed will you be when the movers arrive?</code> | Question — generated/display copy |
| 116 | <code>What kind of protection do you want?</code> | Question — generated/display copy |
| 117 | <code>What arrival window works for you?</code> | Question — generated/display copy |
| 126 | <code>Current home</code> | Question — option/list label |
| 133 | <code>Destination home</code> | Question — option/list label |
| 142 | <code>Storage size</code> | Question — option/list label |
| 144 | <code>Large</code> | Question — option/list label |
| 144 | <code>Medium</code> | Question — option/list label |
| 144 | <code>Small</code> | Question — option/list label |
| 149 | <code>Storage fullness</code> | Question — option/list label |
| 151 | <code>1/2</code> | Question — option/list label |
| 151 | <code>1/4</code> | Question — option/list label |
| 151 | <code>3/4</code> | Question — option/list label |
| 151 | <code>Full</code> | Question — option/list label |
| 157 | <code>Storage unit address or city (optional)</code> | Question — field placeholder/helper |
| 163 | <code>Origin access</code> | Question — option/list label |
| 172 | <code>Destination access</code> | Question — option/list label |
| 180 | <code>Packing status</code> | Question — generated/display copy |
| 181 | <code>Packed before arrival</code> | Question — screen text |
| 182 | <code>Some boxes unpacked</code> | Question — screen text |
| 183 | <code>Not sure yet</code> | Question — screen text |
| 189 | <code>Protection</code> | Question — option/list label |
| 192 | <code>Full-value protection</code> | Question — option/list label |
| 192 | <code>Standard valuation</code> | Question — option/list label |
| 196 | <code>Example: 8–10 AM</code> | Question — field placeholder/helper |
| 221 | <code>Yes</code> | Question — generated/display copy |
| 224 | <code>No</code> | Question — generated/display copy |
| 245 | <code>Not selected</code> | Question — accessibility copy |
| 245 | <code>Selected</code> | Question — accessibility copy |

### `Peezy 4.0/Tasks/Task Cards/MoversBookingReviewView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 16 | <code>Book your movers</code> | MoversBookingReviewView — heading/title |
| 20 | <code>Send the booking request</code> | MoversBookingReviewView — screen text |
| 35 | <code>Anything the company should know?</code> | MoversBookingReviewView — field placeholder/helper |
| 55 | <code>Request this company</code> | MoversBookingReviewView — generated/display copy |
| 55 | <code>Sending…</code> | MoversBookingReviewView — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/MoversCaptureCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>Book your movers</code> | MoversCaptureCard — heading/title |
| 25 | <code>First, let's measure the move</code> | MoversCaptureCard — screen text |
| 30 | <code>A room-by-room scan gives every company the same scope. If video isn't an option, home details still produce a wider estimate range.</code> | MoversCaptureCard — screen text |
| 41 | <code>Scan my home</code> | MoversCaptureCard — generated/display copy |
| 44 | <code>Use home details instead</code> | MoversCaptureCard — button/action label |
| 51 | <code>Not now</code> | MoversCaptureCard — button/action label |

### `Peezy 4.0/Tasks/Task Cards/MoversComparisonView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 18 | <code>Book your movers</code> | MoversComparisonView — heading/title |
| 21 | <code>Same scope. Three prices.</code> | MoversComparisonView — screen text |
| 25 | <code>Ordered by estimated total.</code> | MoversComparisonView — screen text |

### `Peezy 4.0/Tasks/Task Cards/MoversConfirmationView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 14 | <code>Book your movers</code> | MoversConfirmationView — heading/title |
| 24 | <code>Request sent to \(vendorName)</code> | MoversConfirmationView — screen text |
| 29 | <code>Same price basis for every mover. If anything changes day-of, that's on them — and on us.</code> | MoversConfirmationView — screen text |
| 34 | <code>We'll confirm the requested window and next steps as soon as the company responds.</code> | MoversConfirmationView — screen text |
| 44 | <code>Done</code> | MoversConfirmationView — alert/confirmation |

### `Peezy 4.0/Tasks/Task Cards/MoversFlowErrorView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>Book your movers</code> | MoversFlowErrorView — heading/title |
| 20 | <code>Couldn't prepare prices</code> | MoversFlowErrorView — option/list label |
| 28 | <code>Try again</code> | MoversFlowErrorView — error message |
| 30 | <code>Close</code> | MoversFlowErrorView — button/action label |

### `Peezy 4.0/Tasks/Task Cards/MoveScopeSummaryView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 19 | <code>Book your movers</code> | MoveScopeSummaryView — heading/title |
| 24 | <code>Here's the scope we're pricing</code> | MoveScopeSummaryView — screen text |
| 36 | <code>Price basis: \(priceBasis)</code> | MoveScopeSummaryView — screen text |
| 50 | <code>Confirm the details</code> | MoveScopeSummaryView — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/PackingReadinessView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 58 | <code>Loading your readiness check…</code> | PackingReadinessView — error message |
| 66 | <code>Moving-day readiness</code> | PackingReadinessView — heading/title |
| 75 | <code>One last readiness check</code> | PackingReadinessView — screen text |
| 81 | <code>Set for \(record.scheduledDate.formatted(date: .abbreviated, time: .omitted)) — the day before your move.</code> | PackingReadinessView — screen text |
| 119 | <code>Done</code> | PackingReadinessView — generated/display copy |
| 122 | <code>Close</code> | PackingReadinessView — button/action label |
| 167 | <code>Not ready</code> | PackingReadinessView — accessibility copy |
| 167 | <code>Ready</code> | PackingReadinessView — accessibility copy |
| 173 | <code>Moving-day readiness</code> | PackingReadinessView — error message |
| 176 | <code>Couldn't load readiness</code> | PackingReadinessView — option/list label |
| 183 | <code>Try again</code> | PackingReadinessView — generated/display copy |
| 185 | <code>Close</code> | PackingReadinessView — button/action label |

### `Peezy 4.0/Tasks/Task Cards/PackingSessionView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 48 | <code>Loading today's session…</code> | PackingSessionView — error message |
| 56 | <code>Packing plan</code> | PackingSessionView — heading/title |
| 66 | <code>Today: \(session.roomLabel). About \(session.estMinutes) minutes.</code> | PackingSessionView — screen text |
| 73 | <code>Here's what's in it</code> | PackingSessionView — screen text |
| 105 | <code>I packed this</code> | PackingSessionView — generated/display copy |
| 105 | <code>Saving…</code> | PackingSessionView — generated/display copy |
| 111 | <code>Do this later</code> | PackingSessionView — heading/title |
| 117 | <code>Close</code> | PackingSessionView — button/action label |
| 132 | <code>Packing plan</code> | PackingSessionView — heading/title |
| 154 | <code>Done</code> | PackingSessionView — generated/display copy |
| 164 | <code>Packing plan</code> | PackingSessionView — error message |
| 167 | <code>Couldn't load this session</code> | PackingSessionView — option/list label |
| 174 | <code>Try again</code> | PackingSessionView — generated/display copy |
| 176 | <code>Close</code> | PackingSessionView — button/action label |

### `Peezy 4.0/Tasks/Task Cards/RemoveItemsFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 19 | <code>Schedule my donation pickup</code> | RemoveItemsFlow — heading/title |
| 77 | <code>What are you looking to do with these items?</code> | RemoveItemsFlow — generated/display copy |
| 78 | <code>Donate them</code> | RemoveItemsFlow — generated/display copy |
| 79 | <code>Have them hauled away</code> | RemoveItemsFlow — generated/display copy |
| 80 | <code>Not sure — help me decide</code> | RemoveItemsFlow — generated/display copy |
| 91 | <code>What types of items are we talking about?</code> | RemoveItemsFlow — generated/display copy |
| 92 | <code>Furniture</code> | RemoveItemsFlow — generated/display copy |
| 93 | <code>Appliances</code> | RemoveItemsFlow — generated/display copy |
| 94 | <code>Electronics</code> | RemoveItemsFlow — generated/display copy |
| 95 | <code>Mattresses</code> | RemoveItemsFlow — generated/display copy |
| 96 | <code>Household / clothing</code> | RemoveItemsFlow — generated/display copy |
| 97 | <code>Outdoor / debris</code> | RemoveItemsFlow — generated/display copy |
| 109 | <code>What condition are most of the items in?</code> | RemoveItemsFlow — generated/display copy |
| 110 | <code>Like new</code> | RemoveItemsFlow — generated/display copy |
| 111 | <code>Gently used</code> | RemoveItemsFlow — generated/display copy |
| 112 | <code>Worn but functional</code> | RemoveItemsFlow — generated/display copy |
| 113 | <code>Needs repair</code> | RemoveItemsFlow — generated/display copy |
| 124 | <code>How much stuff are we talking about?</code> | RemoveItemsFlow — generated/display copy |
| 125 | <code>A few small items</code> | RemoveItemsFlow — generated/display copy |
| 126 | <code>Several large items</code> | RemoveItemsFlow — generated/display copy |
| 127 | <code>A full room's worth</code> | RemoveItemsFlow — generated/display copy |
| 128 | <code>Multiple rooms</code> | RemoveItemsFlow — generated/display copy |
| 139 | <code>Where are the items right now?</code> | RemoveItemsFlow — generated/display copy |
| 140 | <code>Inside home — ground floor</code> | RemoveItemsFlow — generated/display copy |
| 141 | <code>Upstairs, basement, or attic</code> | RemoveItemsFlow — generated/display copy |
| 142 | <code>Garage</code> | RemoveItemsFlow — generated/display copy |
| 143 | <code>Curbside or driveway</code> | RemoveItemsFlow — generated/display copy |
| 154 | <code>Do you need them picked up, or can you drop them off?</code> | RemoveItemsFlow — generated/display copy |
| 155 | <code>I need pickup</code> | RemoveItemsFlow — generated/display copy |
| 156 | <code>I can drop off</code> | RemoveItemsFlow — generated/display copy |
| 157 | <code>Either works</code> | RemoveItemsFlow — generated/display copy |
| 168 | <code>We'll find the best option for your items and get it scheduled.</code> | RemoveItemsFlow — generated/display copy |
| 169 | <code>Response times are typically 24–48 hours.</code> | RemoveItemsFlow — helper/subtext |

### `Peezy 4.0/Tasks/Task Cards/RentTruckFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Rent my moving truck</code> | RentTruckFlow — heading/title |
| 52 | <code>What type of rental?</code> | RentTruckFlow — generated/display copy |
| 53 | <code>One-way rental</code> | RentTruckFlow — generated/display copy |
| 54 | <code>Return to same location</code> | RentTruckFlow — generated/display copy |
| 64 | <code>We'll compare options from the major rental companies and get you the best deal.</code> | RentTruckFlow — option/list label |
| 65 | <code>Response times are typically 24–48 hours.</code> | RentTruckFlow — option/list label |

### `Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 18 | <code>Sell what I don't need</code> | SellItemsFlow — heading/title |
| 76 | <code>What types of items are you selling?</code> | SellItemsFlow — generated/display copy |
| 77 | <code>Furniture</code> | SellItemsFlow — generated/display copy |
| 78 | <code>Appliances</code> | SellItemsFlow — generated/display copy |
| 79 | <code>Electronics</code> | SellItemsFlow — generated/display copy |
| 80 | <code>Clothing / household</code> | SellItemsFlow — generated/display copy |
| 81 | <code>Outdoor items</code> | SellItemsFlow — generated/display copy |
| 93 | <code>Roughly, what do you think everything is worth?</code> | SellItemsFlow — generated/display copy |
| 94 | <code>Under $500</code> | SellItemsFlow — generated/display copy |
| 95 | <code>$500 – $2,000</code> | SellItemsFlow — generated/display copy |
| 96 | <code>$2,000 – $5,000</code> | SellItemsFlow — generated/display copy |
| 97 | <code>$5,000+</code> | SellItemsFlow — generated/display copy |
| 108 | <code>Which platforms are you open to?</code> | SellItemsFlow — generated/display copy |
| 109 | <code>Facebook Marketplace</code> | SellItemsFlow — generated/display copy |
| 110 | <code>OfferUp</code> | SellItemsFlow — generated/display copy |
| 111 | <code>Craigslist</code> | SellItemsFlow — generated/display copy |
| 112 | <code>Consignment store</code> | SellItemsFlow — generated/display copy |
| 113 | <code>Any of them</code> | SellItemsFlow — generated/display copy |
| 125 | <code>We'll put together a selling plan based on what you've got and where to list it.</code> | SellItemsFlow — generated/display copy |
| 126 | <code>Response times are typically 24–48 hours.</code> | SellItemsFlow — helper/subtext |

### `Peezy 4.0/Tasks/Task Cards/SetupInternetFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 14 | <code>Set up my internet</code> | SetupInternetFlow — heading/title |
| 25 | <code>Kansas City</code> | SetupInternetFlow — generated/display copy |
| 57 | <code>Other internet providers</code> | SetupInternetFlow — alert/confirmation |
| 62 | <code>\(plan.provider) — \(plan.tier)</code> | SetupInternetFlow — button/action label |
| 66 | <code>Cancel</code> | SetupInternetFlow — button/action label |
| 105 | <code>Plans for \(addressLabel)</code> | SetupInternetFlow — screen text |
| 113 | <code>Curated Kansas City-area options. Each provider confirms availability and final terms for your exact address.</code> | SetupInternetFlow — option/list label |
| 121 | <code>Loading plans…</code> | SetupInternetFlow — generated/display copy |
| 139 | <code>See other providers</code> | SetupInternetFlow — button/action label |
| 156 | <code>I checked availability</code> | SetupInternetFlow — generated/display copy |
| 156 | <code>Saving…</code> | SetupInternetFlow — generated/display copy |
| 160 | <code>Available after opening a provider plan</code> | SetupInternetFlow — accessibility copy |
| 182 | <code>Try again</code> | SetupInternetFlow — button/action label |
| 205 | <code>We couldn't load internet plans. Check your connection and try again.</code> | SetupInternetFlow — error message |
| 213 | <code>Kansas City</code> | SetupInternetFlow — generated/display copy |
| 218 | <code>We couldn't load internet plans. Check your connection and try again.</code> | SetupInternetFlow — error message |
| 267 | <code>, </code> | SetupInternetFlow — generated/display copy |
| 270 | <code> </code> | SetupInternetFlow — generated/display copy |
| 272 | <code>Kansas City</code> | SetupInternetFlow — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 81 | <code>Building your kit…</code> | SuppliesKitView — error message |
| 89 | <code>Packing supplies</code> | SuppliesKitView — heading/title |
| 98 | <code>Your packing kit</code> | SuppliesKitView — screen text |
| 104 | <code>Sized from your home scan</code> | SuppliesKitView — screen text |
| 109 | <code>Small boxes</code> | SuppliesKitView — generated/display copy |
| 110 | <code>Medium boxes</code> | SuppliesKitView — generated/display copy |
| 111 | <code>Large boxes</code> | SuppliesKitView — generated/display copy |
| 112 | <code>Wardrobe boxes</code> | SuppliesKitView — generated/display copy |
| 113 | <code>Dish packs</code> | SuppliesKitView — generated/display copy |
| 114 | <code>Tape rolls</code> | SuppliesKitView — generated/display copy |
| 115 | <code>Packing-paper packs</code> | SuppliesKitView — generated/display copy |
| 116 | <code>Protective-wrap rolls</code> | SuppliesKitView — generated/display copy |
| 117 | <code>Mattress bags</code> | SuppliesKitView — generated/display copy |
| 124 | <code>Estimated kit: \(formattedPrice(kit.totalPriceCents))</code> | SuppliesKitView — screen text |
| 131 | <code>Deliver by \(deliveryBy.formatted(date: .abbreviated, time: .omitted)) — before your first packing session.</code> | SuppliesKitView — screen text |
| 157 | <code>Order my kit</code> | SuppliesKitView — generated/display copy |
| 157 | <code>Sending…</code> | SuppliesKitView — generated/display copy |
| 163 | <code>Customize</code> | SuppliesKitView — heading/title |
| 171 | <code>No thanks</code> | SuppliesKitView — button/action label |
| 180 | <code>Close</code> | SuppliesKitView — button/action label |
| 194 | <code>Packing supplies</code> | SuppliesKitView — heading/title |
| 201 | <code>Kit request sent. Peezy is lining up the supplies before packing starts.</code> | SuppliesKitView — screen text |
| 210 | <code>Done</code> | SuppliesKitView — generated/display copy |
| 222 | <code>Packing supplies</code> | SuppliesKitView — error message |
| 225 | <code>Couldn't load your kit</code> | SuppliesKitView — option/list label |
| 230 | <code>Try again</code> | SuppliesKitView — generated/display copy |
| 233 | <code>Close</code> | SuppliesKitView — button/action label |
| 245 | <code>\(value)</code> | SuppliesKitView — screen text |
| 444 | <code>Your move profile is missing. Add it in Settings before ordering the kit.</code> | SuppliesKitSubmissionError — error message |
| 469 | <code>Small boxes</code> | KitField — generated/display copy |
| 470 | <code>Medium boxes</code> | KitField — generated/display copy |
| 471 | <code>Large boxes</code> | KitField — generated/display copy |
| 472 | <code>Wardrobe boxes</code> | KitField — generated/display copy |
| 473 | <code>Dish packs</code> | KitField — generated/display copy |
| 474 | <code>Tape rolls</code> | KitField — generated/display copy |
| 475 | <code>Paper packs</code> | KitField — generated/display copy |
| 476 | <code>Wrap rolls</code> | KitField — generated/display copy |
| 477 | <code>Mattress bags</code> | KitField — generated/display copy |
| 503 | <code>Item \(questionIndex + 1) of \(KitField.allCases.count)</code> | KitField — screen text |
| 508 | <code>How many \(currentField.label.lowercased()) do you want?</code> | KitField — screen text |
| 520 | <code>Estimated kit</code> | KitField — screen text |
| 529 | <code>Save</code> | KitField — generated/display copy |
| 529 | <code>Saving…</code> | KitField — generated/display copy |
| 530 | <code>Continue</code> | KitField — generated/display copy |
| 538 | <code>Customize kit</code> | KitField — heading/title |
| 541 | <code>Cancel</code> | KitField — button/action label |
| 546 | <code>Back</code> | KitField — button/action label |
| 587 | <code>\(value.wrappedValue)</code> | KitField — screen text |

### `Peezy 4.0/Tasks/Views/PendingConfirmation.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>Reset your inventory?</code> | PendingConfirmation — generated/display copy |
| 17 | <code>This deletes every room scan and item you've submitted. You'll need to scan your home again from scratch. This can't be undone.</code> | PendingConfirmation — generated/display copy |
| 20 | <code>Yes, reset everything</code> | PendingConfirmation — generated/display copy |
| 21 | <code>Keep my inventory</code> | PendingConfirmation — generated/display copy |

### `Peezy 4.0/Tasks/Views/ResetInventoryOverlay.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 8 | <code>Resetting inventory...</code> | ResetInventoryOverlay — generated/display copy |

### `Peezy 4.0/Tasks/Views/TaskRowButtons.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 80 | <code>Open Task</code> | TaskRowButtons — heading/title |
| 84 | <code>Open Task</code> | TaskRowButtons — heading/title |
| 85 | <code>Mark as complete</code> | TaskRowButtons — heading/title |
| 86 | <code>Reset inventory</code> | TaskRowButtons — heading/title |
| 90 | <code>Open Task</code> | TaskRowButtons — heading/title |
| 91 | <code>Mark as complete</code> | TaskRowButtons — heading/title |
| 95 | <code>Open Task</code> | TaskRowButtons — heading/title |
| 98 | <code>Reset inventory</code> | TaskRowButtons — heading/title |
| 100 | <code>Undo</code> | TaskRowButtons — heading/title |

### `Peezy 4.0/Tasks/Views/TaskRowHeader.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 85 | <code>You're on it</code> | TaskRowHeader — generated/display copy |
| 87 | <code>Matching vendors</code> | TaskRowHeader — generated/display copy |
| 87 | <code>Peezy is on it</code> | TaskRowHeader — generated/display copy |
| 91 | <code>Returns \(returnDate.formatted(date: .abbreviated, time: .omitted))</code> | TaskRowHeader — generated/display copy |

### `Peezy 4.0/Tasks/Views/TasksEmptyState.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 10 | <code>No tasks yet</code> | TasksEmptyState — screen text |
| 14 | <code>Tasks will appear here after your assessment.</code> | TasksEmptyState — screen text |

### `Peezy 4.0/Tasks/Views/TasksErrorBanner.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>Couldn't load tasks</code> | TasksErrorBanner — screen text |
| 27 | <code>Tap to retry</code> | TasksErrorBanner — screen text |

### `Peezy 4.0/Tasks/Views/TasksHeader.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 10 | <code>\(firstName)'s Task List</code> | TasksHeader — generated/display copy |
| 12 | <code>Task List</code> | TasksHeader — generated/display copy |
| 32 | <code>Return to home</code> | TasksHeader — accessibility copy |

### `Peezy 4.0/Tasks/Views/TasksList.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 28 | <code>You're on track. New tasks drop in daily.</code> | TasksList — generated/display copy |
| 34 | <code>Snoozed</code> | TasksList — heading/title |
| 43 | <code>Nothing in the works yet.</code> | TasksList — generated/display copy |
| 46 | <code>You're on it</code> | TasksList — heading/title |
| 52 | <code>Peezy is on it</code> | TasksList — heading/title |
| 61 | <code>Completed tasks will stack up here.</code> | TasksList — generated/display copy |

### `Peezy 4.0/Tasks/Views/TasksTabBar.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 39 | <code>\(count)</code> | TasksTabBar — screen text |

### `Peezy 4.0/Tasks/Views/TaskTab.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>To-Do</code> | TaskTab — generated/display copy |
| 5 | <code>In Progress</code> | TaskTab — generated/display copy |
| 6 | <code>Done</code> | TaskTab — generated/display copy |

## Data-driven and callable strings

### `functions/flowDefinitionsData.json`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Request my time off</code> | FlowEngine schedule_time_off_work — taskTitle |
| 15 | <code>Block the day after move day — unpacking always runs longer than expected. Without time off, you'll be answering Slack with a couch on your back.</code> | FlowEngine schedule_time_off_work — body |
| 26 | <code>Update my employer records</code> | FlowEngine update_employer_records — taskTitle |
| 37 | <code>Confirm payroll updated 'work state for taxes' — addresses don't sync. Wrong state withholding turns next April into a W-2 nightmare.</code> | FlowEngine update_employer_records — body |
| 48 | <code>Buy packing supplies</code> | FlowEngine buy_packing_supplies — taskTitle |
| 59 | <code>Buy 20% more small boxes than you think — books, kitchen stuff, and bathroom items fill them fast. Big boxes get dangerously heavy.</code> | FlowEngine buy_packing_supplies — body |
| 70 | <code>Defrost my freezer</code> | FlowEngine defrost_freezer — taskTitle |
| 81 | <code>A freezer that's not fully defrosted leaks across the moving truck floor and ruins cardboard boxes on contact.</code> | FlowEngine defrost_freezer — body |
| 92 | <code>Do the deep clean</code> | FlowEngine diy_deep_cleaning — taskTitle |
| 103 | <code>Stock up first</code> | FlowEngine diy_deep_cleaning — infoTitle |
| 104 | <code>Pack a 'last bag' with cleaning supplies — load it onto the truck last. Once boxes are sealed, finding a sponge becomes a 30-minute hunt.</code> | FlowEngine diy_deep_cleaning — body |
| 110 | <code>Clean inside the oven and fridge first — they're the top deduction trigger. One missed area can cost you hundreds in deposit deductions.</code> | FlowEngine diy_deep_cleaning — body |
| 121 | <code>Do the final touch-up</code> | FlowEngine diy_final_cleaning — taskTitle |
| 132 | <code>Bring a flashlight — corners and closets hide more than you think. A forgotten item or dusty corner is exactly what landlords cite.</code> | FlowEngine diy_final_cleaning — body |
| 143 | <code>Forward my mail</code> | FlowEngine forward_mail_usps — taskTitle |
| 154 | <code>Set up USPS mail forwarding online ($1.10 fee). Takes effect in 7-10 business days — do this 2 weeks before move day. Forwarding applies to the whole household, not individuals.</code> | FlowEngine forward_mail_usps — body |
| 165 | <code>Update my child's school</code> | FlowEngine coa_schools — taskTitle |
| 176 | <code>Contact the registrar with your new address and proof of residency. Also update emergency contacts, bus routes, and after-school programs.</code> | FlowEngine coa_schools — body |
| 187 | <code>Update my daycare</code> | FlowEngine transfer_daycare — taskTitle |
| 198 | <code>Give your current daycare 2-4 weeks written notice. Request copies of developmental records and immunization history. Ask for recommendations near your new address.</code> | FlowEngine transfer_daycare — body |
| 209 | <code>Find my new daycare</code> | FlowEngine setup_daycare — taskTitle |
| 220 | <code>Start calling providers now — waitlists for infant and toddler spots can be 3-6 months. Contact at least 5 providers near your new address, ask about openings for your child's age group, and get on every waitlist. It costs nothing and saves you from scrambling after the move.</code> | FlowEngine setup_daycare — body |
| 231 | <code>Set up my new utilities</code> | FlowEngine setup_utilities — taskTitle |
| 242 | <code>~2.5 hrs</code> | FlowEngine setup_utilities — timeSaved |
| 259 | <code>Is this your new address?</code> | FlowEngine setup_utilities — question |
| 267 | <code>We'll contact the utility providers to set up service at your new address before you arrive.</code> | FlowEngine setup_utilities — body |
| 268 | <code>Response times are typically 24–48 hours.</code> | FlowEngine setup_utilities — subtext |
| 273 | <code>Get a 'letter of credit' from your old utility — waives the deposit.</code> | FlowEngine setup_utilities — body |
| 284 | <code>Cancel my utilities</code> | FlowEngine cancel_utilities — taskTitle |
| 295 | <code>~1.25 hrs</code> | FlowEngine cancel_utilities — timeSaved |
| 312 | <code>Is this your current address?</code> | FlowEngine cancel_utilities — question |
| 320 | <code>We'll contact each provider to schedule shutoffs at your current address after you move out.</code> | FlowEngine cancel_utilities — body |
| 321 | <code>Response times are typically 24–48 hours.</code> | FlowEngine cancel_utilities — subtext |
| 326 | <code>Give them your forwarding address — credit refunds arrive by mail.</code> | FlowEngine cancel_utilities — body |
| 337 | <code>Transfer my utilities</code> | FlowEngine transfer_utilities — taskTitle |
| 348 | <code>~1.5 hrs</code> | FlowEngine transfer_utilities — timeSaved |
| 365 | <code>Is this your new address?</code> | FlowEngine transfer_utilities — question |
| 373 | <code>We'll contact each provider to transfer service to your new address with no overlap in billing.</code> | FlowEngine transfer_utilities — body |
| 374 | <code>Response times are typically 24–48 hours.</code> | FlowEngine transfer_utilities — subtext |
| 379 | <code>Same provider = no new deposit, no credit check, no setup fee.</code> | FlowEngine transfer_utilities — body |
| 390 | <code>Handle my vet</code> | FlowEngine manage_vet — taskTitle |
| 401 | <code>What would you like to do?</code> | FlowEngine manage_vet — question |
| 406 | <code>Update my address</code> | FlowEngine manage_vet — label |
| 411 | <code>Find a new one</code> | FlowEngine manage_vet — label |
| 445 | <code>Who's your vet?</code> | FlowEngine manage_vet — question |
| 446 | <code>Search for a veterinary clinic...</code> | FlowEngine manage_vet — placeholder |
| 453 | <code>We'll reach out to your vet and get your address updated.</code> | FlowEngine manage_vet — body |
| 454 | <code>Response times are typically 24–48 hours.</code> | FlowEngine manage_vet — subtext |
| 459 | <code>Most vet offices let you update your address by calling the front desk or through their patient portal.</code> | FlowEngine manage_vet — body |
| 469 | <code>Want help transferring your records?</code> | FlowEngine manage_vet — question |
| 485 | <code>Who's your current vet?</code> | FlowEngine manage_vet — question |
| 486 | <code>Search for a veterinary clinic...</code> | FlowEngine manage_vet — placeholder |
| 493 | <code>Would you like help finding a new vet near your new place?</code> | FlowEngine manage_vet — question |
| 516 | <code>We'll help find you a new vet near your new place.</code> | FlowEngine manage_vet — body |
| 517 | <code>Response times are typically 24–48 hours.</code> | FlowEngine manage_vet — subtext |
| 524 | <code>We'll transfer your records and help find you a new vet.</code> | FlowEngine manage_vet — body |
| 530 | <code>We'll transfer your records. You're all set to find a new one on your own.</code> | FlowEngine manage_vet — body |
| 537 | <code>Call the front desk to request a records transfer — make sure vaccination records are included. For the new place, ask other pet owners in your new neighborhood for recommendations.</code> | FlowEngine manage_vet — body |
| 548 | <code>Handle my pharmacy</code> | FlowEngine transfer_pharmacy_records — taskTitle |
| 559 | <code>What would you like to do?</code> | FlowEngine transfer_pharmacy_records — question |
| 564 | <code>Update my address</code> | FlowEngine transfer_pharmacy_records — label |
| 569 | <code>Find a new one</code> | FlowEngine transfer_pharmacy_records — label |
| 603 | <code>Which pharmacy do you use?</code> | FlowEngine transfer_pharmacy_records — question |
| 604 | <code>Search for a pharmacy...</code> | FlowEngine transfer_pharmacy_records — placeholder |
| 611 | <code>We'll reach out to your pharmacy and get your address updated.</code> | FlowEngine transfer_pharmacy_records — body |
| 612 | <code>Response times are typically 24–48 hours.</code> | FlowEngine transfer_pharmacy_records — subtext |
| 617 | <code>Most pharmacies let you update your address online or through their app. Have your prescription numbers handy.</code> | FlowEngine transfer_pharmacy_records — body |
| 627 | <code>Want help transferring your prescriptions?</code> | FlowEngine transfer_pharmacy_records — question |
| 643 | <code>Which pharmacy do you use?</code> | FlowEngine transfer_pharmacy_records — question |
| 644 | <code>Search for a pharmacy...</code> | FlowEngine transfer_pharmacy_records — placeholder |
| 651 | <code>Would you like help finding a new pharmacy near your new place?</code> | FlowEngine transfer_pharmacy_records — question |
| 674 | <code>We'll help find you a new pharmacy near your new place.</code> | FlowEngine transfer_pharmacy_records — body |
| 675 | <code>Response times are typically 24–48 hours.</code> | FlowEngine transfer_pharmacy_records — subtext |
| 682 | <code>We'll transfer your prescriptions and help find you a new pharmacy.</code> | FlowEngine transfer_pharmacy_records — body |
| 688 | <code>We'll transfer your prescriptions. You're all set to find a new one on your own.</code> | FlowEngine transfer_pharmacy_records — body |
| 695 | <code>Most pharmacies can transfer prescriptions with just a phone call to the new location. Give them your name, date of birth, and current pharmacy — they handle the rest.</code> | FlowEngine transfer_pharmacy_records — body |
| 706 | <code>Update my license address</code> | FlowEngine handle_dmv_local — taskTitle |
| 717 | <code>Check your state — many let you update online without an appointment. An outdated address can void traffic ticket service and jury duty notices.</code> | FlowEngine handle_dmv_local — body |
| 728 | <code>Handle the DMV</code> | FlowEngine handle_dmv_interstate — taskTitle |
| 739 | <code>New state license</code> | FlowEngine handle_dmv_interstate — infoTitle |
| 740 | <code>Request REAL ID — TSA needs a new one in your new state. Driving past the deadline on an out-of-state license is a moving violation.</code> | FlowEngine handle_dmv_interstate — body |
| 746 | <code>Vehicle registration</code> | FlowEngine handle_dmv_interstate — infoTitle |
| 748 | <code>Update auto insurance first — DMV won't register without it. Outdated tags risk tickets, towing, and insurance denial in a crash.</code> | FlowEngine handle_dmv_interstate — body |
| 759 | <code>Reserve my move-out access</code> | FlowEngine reserve_access_old — taskTitle |
| 770 | <code>~1 hr</code> | FlowEngine reserve_access_old — timeSaved |
| 787 | <code>Is this where you're loading from?</code> | FlowEngine reserve_access_old — question |
| 795 | <code>Is this your move date?</code> | FlowEngine reserve_access_old — question |
| 801 | <code>We'll contact your current building and reserve {rowsList} for move day.</code> | FlowEngine reserve_access_old — body |
| 803 | <code>a truck-sized loading spot</code> | FlowEngine reserve_access_old — parking |
| 804 | <code>the service elevator window</code> | FlowEngine reserve_access_old — elevator |
| 806 | <code>Response times are typically 24–48 hours.</code> | FlowEngine reserve_access_old — subtext |
| 811 | <code>Reserve two adjacent spots — trucks need ramp clearance too.</code> | FlowEngine reserve_access_old — body |
| 822 | <code>Reserve my move-in access</code> | FlowEngine reserve_access_new — taskTitle |
| 833 | <code>~1 hr</code> | FlowEngine reserve_access_new — timeSaved |
| 850 | <code>Is this where you're unloading?</code> | FlowEngine reserve_access_new — question |
| 858 | <code>Is this your move date?</code> | FlowEngine reserve_access_new — question |
| 864 | <code>We'll contact your new building and reserve {rowsList} for move day.</code> | FlowEngine reserve_access_new — body |
| 866 | <code>a truck-sized spot</code> | FlowEngine reserve_access_new — parking |
| 867 | <code>the service elevator window</code> | FlowEngine reserve_access_new — elevator |
| 869 | <code>Response times are typically 24–48 hours.</code> | FlowEngine reserve_access_new — subtext |
| 874 | <code>Ask the building to cone off the spot the night before.</code> | FlowEngine reserve_access_new — body |
| 885 | <code>Protect my deposit</code> | FlowEngine protect_deposit — taskTitle |
| 896 | <code>Document the unit</code> | FlowEngine protect_deposit — infoTitle |
| 897 | <code>Shoot video too — it captures context photos miss. Slumlords count on you not having proof.</code> | FlowEngine protect_deposit — body |
| 903 | <code>Return every device</code> | FlowEngine protect_deposit — infoTitle |
| 904 | <code>A missing $5 fob can cost $200 in lock-change charges. Photograph everything you're returning the moment you hand it over.</code> | FlowEngine protect_deposit — body |
| 915 | <code>Handle the school transfer</code> | FlowEngine school_transfer — taskTitle |
| 926 | <code>Notify the current school</code> | FlowEngine school_transfer — infoTitle |
| 927 | <code>Give the school at least 2-4 weeks written notice. Request sealed transcripts and a records transfer packet — the new school will need immunization records, IEP documents if applicable, and proof of completed coursework.</code> | FlowEngine school_transfer — body |
| 933 | <code>Enroll in the new school</code> | FlowEngine school_transfer — infoTitle |
| 934 | <code>Contact the new district's enrollment office before you move. You'll need proof of residency at the new address, immunization records, and your child's birth certificate. Many districts let you start the paperwork online.</code> | FlowEngine school_transfer — body |
| 945 | <code>Move my medical records</code> | FlowEngine medical_records — taskTitle |
| 956 | <code>~1.5 hrs</code> | FlowEngine medical_records — timeSaved |
| 976 | <code>Who's your primary care doctor?</code> | FlowEngine medical_records — question |
| 977 | <code>Search for a doctor's office...</code> | FlowEngine medical_records — placeholder |
| 981 | <code>Who's your dentist?</code> | FlowEngine medical_records — question |
| 982 | <code>Search for a dental office...</code> | FlowEngine medical_records — placeholder |
| 986 | <code>Who's your specialist?</code> | FlowEngine medical_records — question |
| 987 | <code>Search for a specialist's office...</code> | FlowEngine medical_records — placeholder |
| 996 | <code>We'll reach out to each office and get your records moving.</code> | FlowEngine medical_records — body |
| 997 | <code>Response times are typically 24–48 hours.</code> | FlowEngine medical_records — subtext |
| 1002 | <code>Call the front desk to request a records transfer — most offices can send them electronically.</code> | FlowEngine medical_records — body |
| 1013 | <code>Handle my money accounts</code> | FlowEngine financial_accounts — taskTitle |
| 1024 | <code>~2 hrs</code> | FlowEngine financial_accounts — timeSaved |
| 1044 | <code>Which bank are you with?</code> | FlowEngine financial_accounts — question |
| 1045 | <code>Search for a bank...</code> | FlowEngine financial_accounts — placeholder |
| 1049 | <code>Which credit card company?</code> | FlowEngine financial_accounts — question |
| 1050 | <code>Search for a card issuer...</code> | FlowEngine financial_accounts — placeholder |
| 1054 | <code>Which brokerage are you with?</code> | FlowEngine financial_accounts — question |
| 1055 | <code>Search for a brokerage...</code> | FlowEngine financial_accounts — placeholder |
| 1059 | <code>Who services your student loans?</code> | FlowEngine financial_accounts — question |
| 1060 | <code>Search for a loan servicer...</code> | FlowEngine financial_accounts — placeholder |
| 1069 | <code>We'll reach out to each of them and get your address updated.</code> | FlowEngine financial_accounts — body |
| 1070 | <code>Response times are typically 24–48 hours.</code> | FlowEngine financial_accounts — subtext |
| 1075 | <code>Update billing addresses before your next statement closes — mismatches trigger fraud alerts and declined transactions.</code> | FlowEngine financial_accounts — body |
| 1086 | <code>Handle my memberships</code> | FlowEngine memberships — taskTitle |
| 1097 | <code>~2 hrs</code> | FlowEngine memberships — timeSaved |
| 1117 | <code>Which gym do you go to?</code> | FlowEngine memberships — question |
| 1118 | <code>Search for a gym...</code> | FlowEngine memberships — placeholder |
| 1122 | <code>Which studio do you go to?</code> | FlowEngine memberships — question |
| 1123 | <code>Search for a yoga studio...</code> | FlowEngine memberships — placeholder |
| 1127 | <code>Which studio do you go to?</code> | FlowEngine memberships — question |
| 1128 | <code>Search for a cycling studio...</code> | FlowEngine memberships — placeholder |
| 1132 | <code>Which spa do you go to?</code> | FlowEngine memberships — question |
| 1133 | <code>Search for a spa...</code> | FlowEngine memberships — placeholder |
| 1137 | <code>Which club are you a member of?</code> | FlowEngine memberships — question |
| 1138 | <code>Search for a club...</code> | FlowEngine memberships — placeholder |
| 1147 | <code>We'll contact each of them — cancellations, transfers, and address updates handled.</code> | FlowEngine memberships — body |
| 1148 | <code>Response times are typically 24–48 hours.</code> | FlowEngine memberships — subtext |
| 1153 | <code>Check your membership terms for cancellation requirements — some need 30 days written notice.</code> | FlowEngine memberships — body |
| 1164 | <code>Line up my storage unit</code> | FlowEngine storage_unit — taskTitle |
| 1175 | <code>Want us to find you the right unit?</code> | FlowEngine storage_unit — question |
| 1176 | <code>~1.5 hrs</code> | FlowEngine storage_unit — timeSaved |
| 1193 | <code>We'll scout units near your new place and come back with the best options.</code> | FlowEngine storage_unit — body |
| 1194 | <code>Response times are typically 24–48 hours.</code> | FlowEngine storage_unit — subtext |
| 1199 | <code>Book two weeks out — first-month-free deals go to early reservations.</code> | FlowEngine storage_unit — body |

### `functions/getWorkflowQualifying.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 29 | <code>workflowId is required</code> | callable error |
| 144 | <code>workflowId, answers, and userId are required</code> | callable error |
| 294 | <code>Failed to submit answers</code> | callable error |

### `functions/index.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 33 | <code>Hey! Thanks for reaching out. We'll get back to you within a few hours during business hours (9am-6pm CT). For urgent issues, reply 'URGENT' and we'll prioritize.</code> | Support chat — first-message auto-acknowledgment |
| 103 | <code>Method not allowed</code> | HTTP error payload |
| 118 | <code>I'm having trouble loading my knowledge base. Try again in a moment.</code> | HTTP text payload |
| 132 | <code>You're moving fast! Give me a moment to catch up. Try again in a few seconds.</code> | HTTP text payload |
| 194 | <code>Something went sideways on my end. Mind trying that again?</code> | HTTP text payload |
| 590 | <code>Must be signed in to delete account.</code> | callable error |
| 636 | <code>Account deletion failed. Please try again or contact support.</code> | callable error |

### `functions/ispPlansData.json`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 7 | <code>Google Fiber</code> | ISP plan catalog google_fiber_core_1_gig — provider |
| 8 | <code>Core 1 Gig</code> | ISP plan catalog google_fiber_core_1_gig — tier |
| 9 | <code>Up to 1 Gbps upload and download</code> | ISP plan catalog google_fiber_core_1_gig — speed |
| 10 | <code>$70/mo</code> | ISP plan catalog google_fiber_core_1_gig — price |
| 11 | <code>Wi-Fi 6E router, installation, and unlimited data included</code> | ISP plan catalog google_fiber_core_1_gig — promo |
| 12 | <code>No annual contract</code> | ISP plan catalog google_fiber_core_1_gig — contract |
| 13 | <code>A straightforward symmetrical fiber option for busy connected homes.</code> | ISP plan catalog google_fiber_core_1_gig — why |
| 22 | <code>AT&amp;T Fiber</code> | ISP plan catalog att_fiber_300 — provider |
| 23 | <code>Internet 300</code> | ISP plan catalog att_fiber_300 — tier |
| 24 | <code>Up to 300 Mbps</code> | ISP plan catalog att_fiber_300 — speed |
| 25 | <code>$35/mo promotional</code> | ISP plan catalog att_fiber_300 — price |
| 26 | <code>New-customer and billing discounts apply; availability is limited</code> | ISP plan catalog att_fiber_300 — promo |
| 27 | <code>No annual contract</code> | ISP plan catalog att_fiber_300 — contract |
| 28 | <code>A lower-cost fiber tier with enough speed for streaming and video calls.</code> | ISP plan catalog att_fiber_300 — why |
| 37 | <code>Xfinity</code> | ISP plan catalog xfinity_300 — provider |
| 38 | <code>300 Mbps</code> | ISP plan catalog xfinity_300 — tier |
| 39 | <code>Up to 300 Mbps</code> | ISP plan catalog xfinity_300 — speed |
| 40 | <code>$45/mo for 5 years</code> | ISP plan catalog xfinity_300 — price |
| 41 | <code>WiFi equipment and unlimited data included; offer ends 7/27/26</code> | ISP plan catalog xfinity_300 — promo |
| 42 | <code>No annual contract</code> | ISP plan catalog xfinity_300 — contract |
| 43 | <code>A price-guaranteed cable option for everyday work, play, and streaming.</code> | ISP plan catalog xfinity_300 — why |
| 52 | <code>Spectrum</code> | ISP plan catalog spectrum_internet_premier — provider |
| 53 | <code>Internet Premier</code> | ISP plan catalog spectrum_internet_premier — tier |
| 54 | <code>Up to 500 Mbps</code> | ISP plan catalog spectrum_internet_premier — speed |
| 55 | <code>$40/mo for year 1</code> | ISP plan catalog spectrum_internet_premier — price |
| 56 | <code>Advanced WiFi available for $10/mo; current offer terms apply</code> | ISP plan catalog spectrum_internet_premier — promo |
| 57 | <code>No contract or data cap</code> | ISP plan catalog spectrum_internet_premier — contract |
| 58 | <code>A mid-tier cable option for households with several active devices.</code> | ISP plan catalog spectrum_internet_premier — why |
| 67 | <code>T-Mobile Home Internet</code> | ISP plan catalog tmobile_rely_home_internet — provider |
| 68 | <code>Rely</code> | ISP plan catalog tmobile_rely_home_internet — tier |
| 69 | <code>Typical download 133–354 Mbps</code> | ISP plan catalog tmobile_rely_home_internet — speed |
| 70 | <code>$50/mo with AutoPay</code> | ISP plan catalog tmobile_rely_home_internet — price |
| 71 | <code>5-year price guarantee and 5G gateway included</code> | ISP plan catalog tmobile_rely_home_internet — promo |
| 72 | <code>No annual contract</code> | ISP plan catalog tmobile_rely_home_internet — contract |
| 73 | <code>A quick self-install wireless option where wired service is inconvenient.</code> | ISP plan catalog tmobile_rely_home_internet — why |

### `functions/joinWaitlist.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 122 | <code>Method not allowed</code> | HTTP error payload |
| 133 | <code>Too many requests. Try again in a minute.</code> | HTTP error payload |
| 141 | <code>Please enter a valid email address.</code> | HTTP error payload |
| 216 | <code>Something went wrong on our end. Please try again.</code> | HTTP error payload |

### `functions/miniAssessmentWorkflows.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 20 | <code>Financial Institutions</code> | Mini assessment address_change_financial — title |
| 21 | <code>Create financial address change list</code> | Mini assessment address_change_financial — taskTitle |
| 25 | <code>Financial Institutions</code> | Mini assessment address_change_financial — title |
| 26 | <code>Let's make sure all your financial accounts get your new address.</code> | Mini assessment address_change_financial — subtitle |
| 27 | <code>Swipe right if you have an account, left if you don't. We'll ask for names after.</code> | Mini assessment address_change_financial — instruction |
| 33 | <code>Do you have a bank or credit union account?</code> | Mini assessment address_change_financial — question |
| 35 | <code>Which bank/credit union?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 36 | <code>Chase, Wells Fargo, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 41 | <code>Do you have any credit cards?</code> | Mini assessment address_change_financial — question |
| 43 | <code>Which credit cards?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 44 | <code>Amex, Discover, Capital One, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 49 | <code>Do you have investment or brokerage accounts?</code> | Mini assessment address_change_financial — question |
| 51 | <code>Which brokerages?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 52 | <code>Fidelity, Schwab, Robinhood, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 57 | <code>Do you have a 401k or IRA?</code> | Mini assessment address_change_financial — question |
| 59 | <code>Which provider?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 60 | <code>Fidelity, Vanguard, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 64 | <code>Do you have any loans (auto, student, personal)?</code> | Mini assessment address_change_financial — question |
| 66 | <code>Which lenders?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 67 | <code>SoFi, Navient, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 72 | <code>Do you have a mortgage?</code> | Mini assessment address_change_financial — question |
| 74 | <code>Which lender?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 75 | <code>Rocket Mortgage, Chase, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 79 | <code>Do you have an HSA or FSA account?</code> | Mini assessment address_change_financial — question |
| 81 | <code>Which provider?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 82 | <code>HealthEquity, Optum, etc.</code> | Mini assessment address_change_financial — textEntryPlaceholder |
| 87 | <code>Financial Accounts</code> | Mini assessment address_change_financial — title |
| 88 | <code>Here's what we found:</code> | Mini assessment address_change_financial — subtitle |
| 89 | <code>Swipe right to add these tasks</code> | Mini assessment address_change_financial — confirmText |
| 90 | <code>Swipe left to make changes</code> | Mini assessment address_change_financial — editText |
| 94 | <code>Update address:</code> | Mini assessment address_change_financial — titlePrefix |
| 107 | <code>Healthcare</code> | Mini assessment address_change_health — title |
| 108 | <code>Create healthcare address change list</code> | Mini assessment address_change_health — taskTitle |
| 112 | <code>Healthcare Providers</code> | Mini assessment address_change_health — title |
| 113 | <code>Let's update your healthcare providers with your new address.</code> | Mini assessment address_change_health — subtitle |
| 114 | <code>Swipe right if you have this, left if you don't.</code> | Mini assessment address_change_health — instruction |
| 120 | <code>Do you have a primary care doctor?</code> | Mini assessment address_change_health — question |
| 122 | <code>Doctor's name or practice?</code> | Mini assessment address_change_health — textEntryPrompt |
| 123 | <code>Dr. Smith, One Medical, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 127 | <code>Do you have a dentist?</code> | Mini assessment address_change_health — question |
| 129 | <code>Dentist's name or practice?</code> | Mini assessment address_change_health — textEntryPrompt |
| 130 | <code>Dr. Jones, Aspen Dental, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 134 | <code>Do you have health insurance?</code> | Mini assessment address_change_health — question |
| 136 | <code>Which provider?</code> | Mini assessment address_change_health — textEntryPrompt |
| 137 | <code>Blue Cross, Aetna, Kaiser, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 141 | <code>Do you have dental insurance?</code> | Mini assessment address_change_health — question |
| 143 | <code>Which provider?</code> | Mini assessment address_change_health — textEntryPrompt |
| 144 | <code>Delta Dental, MetLife, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 148 | <code>Do you have vision insurance or an eye doctor?</code> | Mini assessment address_change_health — question |
| 150 | <code>Provider or doctor?</code> | Mini assessment address_change_health — textEntryPrompt |
| 151 | <code>VSP, LensCrafters, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 155 | <code>Do you see a therapist or counselor?</code> | Mini assessment address_change_health — question |
| 157 | <code>Therapist's name?</code> | Mini assessment address_change_health — textEntryPrompt |
| 158 | <code>Name or practice</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 162 | <code>Do you see any specialists?</code> | Mini assessment address_change_health — question |
| 164 | <code>Which specialists?</code> | Mini assessment address_change_health — textEntryPrompt |
| 165 | <code>Dermatologist, cardiologist, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 170 | <code>Do you have a regular pharmacy?</code> | Mini assessment address_change_health — question |
| 172 | <code>Which pharmacy?</code> | Mini assessment address_change_health — textEntryPrompt |
| 173 | <code>CVS, Walgreens, etc.</code> | Mini assessment address_change_health — textEntryPlaceholder |
| 178 | <code>Healthcare Providers</code> | Mini assessment address_change_health — title |
| 179 | <code>Here's what we found:</code> | Mini assessment address_change_health — subtitle |
| 180 | <code>Swipe right to add these tasks</code> | Mini assessment address_change_health — confirmText |
| 181 | <code>Swipe left to make changes</code> | Mini assessment address_change_health — editText |
| 185 | <code>Update address:</code> | Mini assessment address_change_health — titlePrefix |
| 198 | <code>Insurance</code> | Mini assessment address_change_insurance — title |
| 199 | <code>Create insurance address change list</code> | Mini assessment address_change_insurance — taskTitle |
| 203 | <code>Insurance Policies</code> | Mini assessment address_change_insurance — title |
| 204 | <code>Insurance companies need your new address - rates can change by location!</code> | Mini assessment address_change_insurance — subtitle |
| 205 | <code>Swipe right if you have this coverage, left if you don't.</code> | Mini assessment address_change_insurance — instruction |
| 211 | <code>Do you have auto insurance?</code> | Mini assessment address_change_insurance — question |
| 213 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 214 | <code>State Farm, Geico, Progressive, etc.</code> | Mini assessment address_change_insurance — textEntryPlaceholder |
| 218 | <code>Do you have renters insurance?</code> | Mini assessment address_change_insurance — question |
| 220 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 221 | <code>Lemonade, State Farm, etc.</code> | Mini assessment address_change_insurance — textEntryPlaceholder |
| 225 | <code>Do you have homeowners insurance?</code> | Mini assessment address_change_insurance — question |
| 227 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 228 | <code>Allstate, Liberty Mutual, etc.</code> | Mini assessment address_change_insurance — textEntryPlaceholder |
| 232 | <code>Do you have life insurance?</code> | Mini assessment address_change_insurance — question |
| 234 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 235 | <code>Northwestern, MetLife, etc.</code> | Mini assessment address_change_insurance — textEntryPlaceholder |
| 239 | <code>Do you have umbrella insurance?</code> | Mini assessment address_change_insurance — question |
| 241 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 242 | <code>Usually same as auto/home</code> | Mini assessment address_change_insurance — textEntryPlaceholder |
| 247 | <code>Insurance Policies</code> | Mini assessment address_change_insurance — title |
| 248 | <code>Here's what we found:</code> | Mini assessment address_change_insurance — subtitle |
| 249 | <code>Swipe right to add these tasks</code> | Mini assessment address_change_insurance — confirmText |
| 250 | <code>Swipe left to make changes</code> | Mini assessment address_change_insurance — editText |
| 254 | <code>Update address:</code> | Mini assessment address_change_insurance — titlePrefix |
| 267 | <code>Fitness &amp; Wellness</code> | Mini assessment address_change_fitness — title |
| 268 | <code>Create fitness membership list</code> | Mini assessment address_change_fitness — taskTitle |
| 272 | <code>Fitness &amp; Wellness</code> | Mini assessment address_change_fitness — title |
| 273 | <code>Let's identify memberships that need to be transferred or canceled.</code> | Mini assessment address_change_fitness — subtitle |
| 274 | <code>Swipe right if you have this membership, left if you don't.</code> | Mini assessment address_change_fitness — instruction |
| 280 | <code>Do you have a gym membership?</code> | Mini assessment address_change_fitness — question |
| 282 | <code>Which gym?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 283 | <code>LA Fitness, Planet Fitness, Equinox, etc.</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 287 | <code>Are you a CrossFit member?</code> | Mini assessment address_change_fitness — question |
| 289 | <code>Which box?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 290 | <code>CrossFit [Name]</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 294 | <code>Do you have a yoga studio membership?</code> | Mini assessment address_change_fitness — question |
| 296 | <code>Which studio?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 297 | <code>CorePower, YogaWorks, etc.</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 301 | <code>Do you have a Pilates membership?</code> | Mini assessment address_change_fitness — question |
| 303 | <code>Which studio?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 304 | <code>Club Pilates, etc.</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 308 | <code>Do you do spin or cycling classes?</code> | Mini assessment address_change_fitness — question |
| 310 | <code>Which studio?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 311 | <code>SoulCycle, Peloton studio, etc.</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 315 | <code>Do you have a pool or swim club membership?</code> | Mini assessment address_change_fitness — question |
| 317 | <code>Which pool/club?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 318 | <code>YMCA, local pool, etc.</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 322 | <code>Are you a country club member?</code> | Mini assessment address_change_fitness — question |
| 324 | <code>Which club?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 325 | <code>Club name</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 329 | <code>Do you have a spa or massage membership?</code> | Mini assessment address_change_fitness — question |
| 331 | <code>Which spa?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 332 | <code>Massage Envy, Hand &amp; Stone, etc.</code> | Mini assessment address_change_fitness — textEntryPlaceholder |
| 337 | <code>Fitness Memberships</code> | Mini assessment address_change_fitness — title |
| 338 | <code>Here's what we found:</code> | Mini assessment address_change_fitness — subtitle |
| 339 | <code>Swipe right to add these tasks</code> | Mini assessment address_change_fitness — confirmText |
| 340 | <code>Swipe left to make changes</code> | Mini assessment address_change_fitness — editText |
| 344 | <code>Cancel/transfer:</code> | Mini assessment address_change_fitness — titlePrefix |
| 357 | <code>Memberships</code> | Mini assessment address_change_memberships — title |
| 358 | <code>Create membership address change list</code> | Mini assessment address_change_memberships — taskTitle |
| 362 | <code>Memberships</code> | Mini assessment address_change_memberships — title |
| 363 | <code>Let's catch any memberships that need your new address.</code> | Mini assessment address_change_memberships — subtitle |
| 364 | <code>Swipe right if you have this, left if you don't.</code> | Mini assessment address_change_memberships — instruction |
| 370 | <code>Do you have a Costco membership?</code> | Mini assessment address_change_memberships — question |
| 376 | <code>Do you have a Sam's Club membership?</code> | Mini assessment address_change_memberships — question |
| 382 | <code>Do you have a BJ's membership?</code> | Mini assessment address_change_memberships — question |
| 388 | <code>Do you have AAA?</code> | Mini assessment address_change_memberships — question |
| 394 | <code>Do you have Amazon Prime?</code> | Mini assessment address_change_memberships — question |
| 400 | <code>Do you have a library card?</code> | Mini assessment address_change_memberships — question |
| 406 | <code>Do you have any museum memberships?</code> | Mini assessment address_change_memberships — question |
| 408 | <code>Which museums?</code> | Mini assessment address_change_memberships — textEntryPrompt |
| 409 | <code>Science museum, art museum, etc.</code> | Mini assessment address_change_memberships — textEntryPlaceholder |
| 414 | <code>Any other memberships?</code> | Mini assessment address_change_memberships — question |
| 416 | <code>What memberships?</code> | Mini assessment address_change_memberships — textEntryPrompt |
| 417 | <code>Professional orgs, clubs, etc.</code> | Mini assessment address_change_memberships — textEntryPlaceholder |
| 423 | <code>Memberships</code> | Mini assessment address_change_memberships — title |
| 424 | <code>Here's what we found:</code> | Mini assessment address_change_memberships — subtitle |
| 425 | <code>Swipe right to add these tasks</code> | Mini assessment address_change_memberships — confirmText |
| 426 | <code>Swipe left to make changes</code> | Mini assessment address_change_memberships — editText |
| 430 | <code>Update address:</code> | Mini assessment address_change_memberships — titlePrefix |
| 443 | <code>Subscriptions</code> | Mini assessment address_change_subscriptions — title |
| 444 | <code>Create subscription address change list</code> | Mini assessment address_change_subscriptions — taskTitle |
| 448 | <code>Subscriptions &amp; Delivery</code> | Mini assessment address_change_subscriptions — title |
| 449 | <code>Let's make sure nothing gets delivered to your old address!</code> | Mini assessment address_change_subscriptions — subtitle |
| 450 | <code>Swipe right if you subscribe to this, left if you don't.</code> | Mini assessment address_change_subscriptions — instruction |
| 456 | <code>Do you get meal kits delivered?</code> | Mini assessment address_change_subscriptions — question |
| 458 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 459 | <code>HelloFresh, Blue Apron, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 463 | <code>Do you get pet food or supplies delivered?</code> | Mini assessment address_change_subscriptions — question |
| 465 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 466 | <code>Chewy, BarkBox, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 470 | <code>Do you subscribe to vitamins or supplements?</code> | Mini assessment address_change_subscriptions — question |
| 472 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 473 | <code>Ritual, Care/of, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 477 | <code>Do you get coffee delivered?</code> | Mini assessment address_change_subscriptions — question |
| 479 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 480 | <code>Trade, Atlas, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 484 | <code>Are you in a wine club?</code> | Mini assessment address_change_subscriptions — question |
| 486 | <code>Which club?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 487 | <code>Winc, local winery, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 491 | <code>Do you get beauty products delivered?</code> | Mini assessment address_change_subscriptions — question |
| 493 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 494 | <code>Ipsy, Birchbox, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 498 | <code>Do you have a clothing subscription?</code> | Mini assessment address_change_subscriptions — question |
| 500 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 501 | <code>Stitch Fix, Rent the Runway, etc.</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 505 | <code>Any other subscription deliveries?</code> | Mini assessment address_change_subscriptions — question |
| 507 | <code>What subscriptions?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 508 | <code>Describe your subscriptions</code> | Mini assessment address_change_subscriptions — textEntryPlaceholder |
| 514 | <code>Subscriptions</code> | Mini assessment address_change_subscriptions — title |
| 515 | <code>Here's what we found:</code> | Mini assessment address_change_subscriptions — subtitle |
| 516 | <code>Swipe right to add these tasks</code> | Mini assessment address_change_subscriptions — confirmText |
| 517 | <code>Swipe left to make changes</code> | Mini assessment address_change_subscriptions — editText |
| 521 | <code>Update address:</code> | Mini assessment address_change_subscriptions — titlePrefix |

### `functions/packageInventory.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 56 | <code>Must be authenticated</code> | callable error |
| 225 | <code>Failed to package inventory</code> | callable fallback error |

### `functions/peezyBrain.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 50 | <code>What's on your mind about the move?</code> | HTTP text payload |
| 129 | <code>I'm getting a lot of requests right now. Give me a sec and try again?</code> | HTTP text payload |
| 139 | <code>Give me just a second - I want to make sure I get this right. Mind trying that again?</code> | HTTP text payload |
| 149 | <code>Something's not working on my end right now. Can you try again in a minute?</code> | HTTP text payload |
| 160 | <code>Having a technical issue on my end. The team's been notified.</code> | HTTP text payload |
| 169 | <code>Something went sideways. Try sending that again?</code> | HTTP text payload |

### `functions/processInventory.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 73 | <code>Must be authenticated</code> | callable error |
| 81 | <code>Missing required fields</code> | callable error |
| 84 | <code>frameCount must be at least 1</code> | callable error |
| 90 | <code>Cannot process another user inventory</code> | callable error |
| 289 | <code>Processing failed</code> | callable fallback error |

### `functions/providerDirectoryData.json`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>Chase</code> | Provider directory chase — name |
| 15 | <code>Bank of America</code> | Provider directory bank_of_america — name |
| 25 | <code>Wells Fargo</code> | Provider directory wells_fargo — name |
| 36 | <code>Citi</code> | Provider directory citi — name |
| 46 | <code>Capital One</code> | Provider directory capital_one — name |
| 56 | <code>U.S. Bank</code> | Provider directory us_bank — name |
| 66 | <code>American Express</code> | Provider directory american_express — name |
| 77 | <code>Discover</code> | Provider directory discover — name |
| 87 | <code>Fidelity</code> | Provider directory fidelity — name |
| 97 | <code>Charles Schwab</code> | Provider directory charles_schwab — name |
| 108 | <code>Vanguard</code> | Provider directory vanguard — name |
| 118 | <code>Ally Bank</code> | Provider directory ally_bank — name |
| 129 | <code>PNC Bank</code> | Provider directory pnc_bank — name |
| 140 | <code>Navy Federal Credit Union</code> | Provider directory navy_federal — name |
| 150 | <code>State Farm</code> | Provider directory state_farm — name |
| 161 | <code>GEICO</code> | Provider directory geico — name |
| 172 | <code>Progressive</code> | Provider directory progressive — name |
| 184 | <code>Allstate</code> | Provider directory allstate — name |
| 195 | <code>Farmers Insurance</code> | Provider directory farmers_insurance — name |
| 206 | <code>USAA</code> | Provider directory usaa — name |
| 217 | <code>Nationwide</code> | Provider directory nationwide — name |
| 228 | <code>Evergy</code> | Provider directory evergy — name |
| 239 | <code>Spire</code> | Provider directory spire — name |
| 250 | <code>KC Water</code> | Provider directory kc_water — name |
| 261 | <code>Missouri American Water</code> | Provider directory missouri_american_water — name |
| 272 | <code>Planet Fitness</code> | Provider directory planet_fitness — name |
| 282 | <code>LA Fitness</code> | Provider directory la_fitness — name |
| 292 | <code>Life Time</code> | Provider directory life_time — name |
| 303 | <code>Crunch Fitness</code> | Provider directory crunch_fitness — name |
| 314 | <code>Gold's Gym</code> | Provider directory golds_gym — name |
| 325 | <code>Anytime Fitness</code> | Provider directory anytime_fitness — name |
| 335 | <code>Orangetheory Fitness</code> | Provider directory orangetheory — name |
| 345 | <code>YMCA</code> | Provider directory ymca — name |
| 355 | <code>Netflix</code> | Provider directory netflix — name |
| 366 | <code>Spotify</code> | Provider directory spotify — name |
| 377 | <code>Amazon Prime</code> | Provider directory amazon_prime — name |
| 387 | <code>Hulu</code> | Provider directory hulu — name |
| 398 | <code>Disney+</code> | Provider directory disney_plus — name |
| 409 | <code>Apple Subscriptions</code> | Provider directory apple_subscriptions — name |
| 420 | <code>YouTube Premium</code> | Provider directory youtube_premium — name |
| 431 | <code>Max</code> | Provider directory max — name |
| 441 | <code>Peacock</code> | Provider directory peacock — name |
| 452 | <code>Verizon</code> | Provider directory verizon — name |
| 463 | <code>AT&amp;T</code> | Provider directory att — name |
| 474 | <code>T-Mobile</code> | Provider directory t_mobile — name |
| 485 | <code>U.S. Cellular</code> | Provider directory us_cellular — name |

### `functions/resolveProvider.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 375 | <code>Must be authenticated</code> | callable error |
| 381 | <code>name, category, and valid intent are required</code> | callable error |

### `functions/submitCheckIn.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 59 | <code>Sign in before submitting a check-in</code> | callable error |

### `functions/submitCheckInCore.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 38 | <code>All four factual answers are required</code> | callable validation error |
| 52 | <code>Final bill must be a positive number</code> | callable validation error |

### `functions/taskCatalogData.json`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 4 | <code>Book your movers</code> | Task catalog BOOK_MOVERS — title |
| 15 | <code>Get binding estimates from three USDOT-licensed movers. Book 8-12 weeks out for summer moves, 4-6 weeks off-season.</code> | Task catalog BOOK_MOVERS — desc |
| 17 | <code>90 secs</code> | Task catalog BOOK_MOVERS — estPeezy |
| 18 | <code>Get a binding estimate — federal law caps your final bill at 110%.</code> | Task catalog BOOK_MOVERS — tips |
| 20 | <code>Booking late means leftover dates, leftover crews, and leftover quality.</code> | Task catalog BOOK_MOVERS — whyNeeded |
| 24 | <code>Book your cleaners</code> | Task catalog BOOK_CLEANERS — title |
| 35 | <code>Schedule a move-out deep clean for the day after your movers finish. Get three quotes and confirm scope in writing.</code> | Task catalog BOOK_CLEANERS — desc |
| 37 | <code>90 secs</code> | Task catalog BOOK_CLEANERS — estPeezy |
| 38 | <code>Insist 'inside appliances' is in writing — most charge extra otherwise.</code> | Task catalog BOOK_CLEANERS — tips |
| 40 | <code>One missed area can cost you your entire security deposit.</code> | Task catalog BOOK_CLEANERS — whyNeeded |
| 44 | <code>Rent your moving truck</code> | Task catalog RENT_TRUCK — title |
| 55 | <code>Compare U-Haul, Penske, and Budget on size, mileage, and total cost. Reserve 4-6 weeks out — earlier in summer.</code> | Task catalog RENT_TRUCK — desc |
| 57 | <code>1 min</code> | Task catalog RENT_TRUCK — estPeezy |
| 58 | <code>Size up if borderline — one trip always beats two.</code> | Task catalog RENT_TRUCK — tips |
| 60 | <code>Late means the wrong size, wrong pickup location, or no truck at all.</code> | Task catalog RENT_TRUCK — whyNeeded |
| 64 | <code>Schedule internet install</code> | Task catalog SETUP_INTERNET — title |
| 71 | <code>Order service 2-3 weeks ahead. Ask for self-install if your home is pre-wired — it saves $50-100 and a technician window.</code> | Task catalog SETUP_INTERNET — desc |
| 73 | <code>90 secs</code> | Task catalog SETUP_INTERNET — estPeezy |
| 74 | <code>Self-install saves $50-100 — confirm your address qualifies first.</code> | Task catalog SETUP_INTERNET — tips |
| 76 | <code>Without it, you're tethering work calls to your phone for days.</code> | Task catalog SETUP_INTERNET — whyNeeded |
| 80 | <code>Sell what you're not bringing</code> | Task catalog SELL_ITEMS — title |
| 94 | <code>List on Facebook Marketplace, OfferUp, or Craigslist 4+ weeks out. Drop the price 10-20% every three days until it sells.</code> | Task catalog SELL_ITEMS — desc |
| 96 | <code>90 secs</code> | Task catalog SELL_ITEMS — estPeezy |
| 97 | <code>Post photos in natural daylight — listings sell twice as fast.</code> | Task catalog SELL_ITEMS — tips |
| 99 | <code>Every unsold item becomes a box you pay to move.</code> | Task catalog SELL_ITEMS — whyNeeded |
| 103 | <code>Schedule donation pickup</code> | Task catalog REMOVE_ITEMS — title |
| 117 | <code>Book a free pickup with Salvation Army or Habitat ReStore 3-4 weeks out — peak season wait times stretch to a month.</code> | Task catalog REMOVE_ITEMS — desc |
| 119 | <code>90 secs</code> | Task catalog REMOVE_ITEMS — estPeezy |
| 120 | <code>Get an itemized receipt at pickup — it's a tax write-off.</code> | Task catalog REMOVE_ITEMS — tips |
| 122 | <code>Last-minute, you'll be hauling furniture to the curb yourself.</code> | Task catalog REMOVE_ITEMS — whyNeeded |
| 126 | <code>Handle your vet</code> | Task catalog MANAGE_VET — title |
| 137 | <code>Update your address if staying. If switching, request vaccination records, lab results, and any chronic-care notes for your new vet.</code> | Task catalog MANAGE_VET — desc |
| 139 | <code>1 min</code> | Task catalog MANAGE_VET — estPeezy |
| 140 | <code>Get the rabies certificate separately — boarding facilities require it on-site.</code> | Task catalog MANAGE_VET — tips |
| 142 | <code>Without records, boarding kennels and ER vets may turn you away.</code> | Task catalog MANAGE_VET — whyNeeded |
| 146 | <code>Forward your mail</code> | Task catalog FORWARD_MAIL_USPS — title |
| 152 | <code>File a USPS change of address ($1.10 verification fee). First-class mail forwards free for 12 months from your start date.</code> | Task catalog FORWARD_MAIL_USPS — desc |
| 154 | <code>30 secs</code> | Task catalog FORWARD_MAIL_USPS — estPeezy |
| 155 | <code>Marketing mail and magazines don't forward — update senders directly.</code> | Task catalog FORWARD_MAIL_USPS — tips |
| 157 | <code>Anything sent to your old address — bills, tax docs, checks — vanishes.</code> | Task catalog FORWARD_MAIL_USPS — whyNeeded |
| 162 | <code>Request your time off</code> | Task catalog SCHEDULE_TIME_OFF_WORK — title |
| 169 | <code>Request 2-3 days minimum: one for packing, moving day, and one to recover. Submit at least four weeks ahead.</code> | Task catalog SCHEDULE_TIME_OFF_WORK — desc |
| 171 | <code>30 secs</code> | Task catalog SCHEDULE_TIME_OFF_WORK — estPeezy |
| 172 | <code>Block the day after move day — unpacking always runs longer than expected.</code> | Task catalog SCHEDULE_TIME_OFF_WORK — tips |
| 174 | <code>Without time off, you'll be answering Slack with a couch on your back.</code> | Task catalog SCHEDULE_TIME_OFF_WORK — whyNeeded |
| 178 | <code>Update employer records</code> | Task catalog UPDATE_EMPLOYER_RECORDS — title |
| 185 | <code>Update your home address with HR. If you crossed state lines, also update your work-state W-4 — addresses and taxes are tracked separately.</code> | Task catalog UPDATE_EMPLOYER_RECORDS — desc |
| 187 | <code>30 secs</code> | Task catalog UPDATE_EMPLOYER_RECORDS — estPeezy |
| 188 | <code>Confirm payroll updated 'work state for taxes' — addresses don't sync.</code> | Task catalog UPDATE_EMPLOYER_RECORDS — tips |
| 190 | <code>Wrong state withholding turns next April into a W-2 nightmare.</code> | Task catalog UPDATE_EMPLOYER_RECORDS — whyNeeded |
| 194 | <code>Cancel your utilities</code> | Task catalog CANCEL_UTILITIES — title |
| 204 | <code>Schedule shutoffs for electric, gas, water, sewer, and trash. Set the date for the day after you move out, not the day of.</code> | Task catalog CANCEL_UTILITIES — desc |
| 206 | <code>1 min</code> | Task catalog CANCEL_UTILITIES — estPeezy |
| 207 | <code>Give them your forwarding address — credit refunds arrive by mail.</code> | Task catalog CANCEL_UTILITIES — tips |
| 209 | <code>Utilities running in your name after move-out keep billing you.</code> | Task catalog CANCEL_UTILITIES — whyNeeded |
| 214 | <code>Set up new utilities</code> | Task catalog SETUP_UTILITIES — title |
| 224 | <code>Call electric, gas, water, and trash providers 2-3 weeks ahead. Schedule activation the day before you arrive — overlap beats outage.</code> | Task catalog SETUP_UTILITIES — desc |
| 226 | <code>1 min</code> | Task catalog SETUP_UTILITIES — estPeezy |
| 227 | <code>Get a 'letter of credit' from your old utility — waives the deposit.</code> | Task catalog SETUP_UTILITIES — tips |
| 229 | <code>Arriving at a dark, waterless house ruins your first night.</code> | Task catalog SETUP_UTILITIES — whyNeeded |
| 234 | <code>Transfer your utilities</code> | Task catalog TRANSFER_UTILITIES — title |
| 244 | <code>Call each provider 1-2 weeks out. Schedule the new address active a day before, the old address shutoff a day after.</code> | Task catalog TRANSFER_UTILITIES — desc |
| 246 | <code>1 min</code> | Task catalog TRANSFER_UTILITIES — estPeezy |
| 247 | <code>Same provider = no new deposit, no credit check, no setup fee.</code> | Task catalog TRANSFER_UTILITIES — tips |
| 249 | <code>Without overlap, you'll lose water mid-clean or power mid-move.</code> | Task catalog TRANSFER_UTILITIES — whyNeeded |
| 254 | <code>Update your child's school</code> | Task catalog COA_SCHOOLS — title |
| 267 | <code>Submit your new address with proof of residency. Update emergency contacts, transportation requests, and pickup authorizations the same day.</code> | Task catalog COA_SCHOOLS — desc |
| 269 | <code>30 secs</code> | Task catalog COA_SCHOOLS — estPeezy |
| 270 | <code>Bus zones change at the address level — confirm yours immediately.</code> | Task catalog COA_SCHOOLS — tips |
| 272 | <code>An old address can drop your kid from the bus route overnight.</code> | Task catalog COA_SCHOOLS — whyNeeded |
| 277 | <code>Find your new daycare</code> | Task catalog SETUP_DAYCARE — title |
| 290 | <code>Get on multiple waitlists immediately — infant care can take 12-24 months. Tour in person and ask about ratios, licensing, and turnover.</code> | Task catalog SETUP_DAYCARE — desc |
| 292 | <code>1 min</code> | Task catalog SETUP_DAYCARE — estPeezy |
| 293 | <code>Send a handwritten thank-you after touring — directors remember you.</code> | Task catalog SETUP_DAYCARE — tips |
| 295 | <code>Waitlists can outlast your move date by a full year.</code> | Task catalog SETUP_DAYCARE — whyNeeded |
| 300 | <code>Update your daycare</code> | Task catalog TRANSFER_DAYCARE — title |
| 313 | <code>Email the director with your new address, updated emergency contacts, and any drop-off or pickup time changes.</code> | Task catalog TRANSFER_DAYCARE — desc |
| 315 | <code>1 min</code> | Task catalog TRANSFER_DAYCARE — estPeezy |
| 316 | <code>Update authorized pickup list in writing — verbal changes don't stick.</code> | Task catalog TRANSFER_DAYCARE — tips |
| 318 | <code>Outdated emergency contacts can block pickup if your child gets hurt.</code> | Task catalog TRANSFER_DAYCARE — whyNeeded |
| 323 | <code>Transfer your pharmacy</code> | Task catalog TRANSFER_PHARMACY_RECORDS — title |
| 336 | <code>Call the new pharmacy with your old pharmacy's name and number — they handle the transfer in minutes for chain stores.</code> | Task catalog TRANSFER_PHARMACY_RECORDS — desc |
| 338 | <code>1 min</code> | Task catalog TRANSFER_PHARMACY_RECORDS — estPeezy |
| 339 | <code>Controlled prescriptions don't transfer — get a new one from your doctor.</code> | Task catalog TRANSFER_PHARMACY_RECORDS — tips |
| 341 | <code>Running out mid-move means an urgent care visit just to refill.</code> | Task catalog TRANSFER_PHARMACY_RECORDS — whyNeeded |
| 346 | <code>Update your auto insurance</code> | Task catalog UPDATE_AUTO_INSURANCE — title |
| 356 | <code>Notify your insurer with the new address before move day. Premiums shift by ZIP code — sometimes by hundreds per year.</code> | Task catalog UPDATE_AUTO_INSURANCE — desc |
| 358 | <code>1 min</code> | Task catalog UPDATE_AUTO_INSURANCE — estPeezy |
| 359 | <code>Get three new quotes the same day — ZIP changes are perfect leverage.</code> | Task catalog UPDATE_AUTO_INSURANCE — tips |
| 361 | <code>Wrong address on file can void your coverage in a claim.</code> | Task catalog UPDATE_AUTO_INSURANCE — whyNeeded |
| 366 | <code>Cancel your condo insurance</code> | Task catalog CANCEL_CONDO_INSURANCE — title |
| 380 | <code>Call your insurer with your move-out date. Schedule cancellation for the day after closing or possession transfer to avoid coverage gaps.</code> | Task catalog CANCEL_CONDO_INSURANCE — desc |
| 382 | <code>1 min</code> | Task catalog CANCEL_CONDO_INSURANCE — estPeezy |
| 383 | <code>Ask for a prorated refund — most insurers owe you for unused months.</code> | Task catalog CANCEL_CONDO_INSURANCE — tips |
| 385 | <code>Cancel too early and a last-day flood becomes your problem alone.</code> | Task catalog CANCEL_CONDO_INSURANCE — whyNeeded |
| 390 | <code>Cancel your renter's insurance</code> | Task catalog CANCEL_RENTERS_INSURANCE — title |
| 403 | <code>Call your insurer to cancel — most do it online in 5 minutes. Schedule the end date for the day you hand back keys.</code> | Task catalog CANCEL_RENTERS_INSURANCE — desc |
| 405 | <code>1 min</code> | Task catalog CANCEL_RENTERS_INSURANCE — estPeezy |
| 406 | <code>Ask for the unused premium back — you're owed a prorated refund.</code> | Task catalog CANCEL_RENTERS_INSURANCE — tips |
| 408 | <code>Canceling before key return leaves your stuff uninsured during the last load.</code> | Task catalog CANCEL_RENTERS_INSURANCE — whyNeeded |
| 413 | <code>Set up condo insurance</code> | Task catalog SETUP_CONDO_INSURANCE — title |
| 427 | <code>Get an HO6 policy effective on closing day. Read the HOA master policy first — it determines whether you need walls-in or full coverage.</code> | Task catalog SETUP_CONDO_INSURANCE — desc |
| 429 | <code>1 min</code> | Task catalog SETUP_CONDO_INSURANCE — estPeezy |
| 430 | <code>Ask the HOA which master policy type — bare walls, walls-in, or all-in.</code> | Task catalog SETUP_CONDO_INSURANCE — tips |
| 432 | <code>The wrong HO6 leaves your floors and cabinets unprotected after a leak.</code> | Task catalog SETUP_CONDO_INSURANCE — whyNeeded |
| 437 | <code>Set up homeowner's insurance</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — title |
| 450 | <code>Lock in coverage 2-3 weeks before closing. Lenders require a paid first year and proof of binder before they'll fund the loan.</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — desc |
| 452 | <code>1 min</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — estPeezy |
| 453 | <code>Quote at least three insurers — premiums vary 30%+ for identical coverage.</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — tips |
| 455 | <code>Without an active binder at closing, the deal stalls and your move with it.</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — whyNeeded |
| 460 | <code>Set up renter's insurance</code> | Task catalog SETUP_RENTERS_INSURANCE — title |
| 473 | <code>Quote online with Lemonade, State Farm, or your auto insurer. Most policies run $15-30/month and bind in under ten minutes.</code> | Task catalog SETUP_RENTERS_INSURANCE — desc |
| 475 | <code>1 min</code> | Task catalog SETUP_RENTERS_INSURANCE — estPeezy |
| 476 | <code>Bundle with auto insurance — usually saves 5-15% on both.</code> | Task catalog SETUP_RENTERS_INSURANCE — tips |
| 478 | <code>One pipe burst can wipe out your belongings without coverage.</code> | Task catalog SETUP_RENTERS_INSURANCE — whyNeeded |
| 483 | <code>Transfer your condo insurance</code> | Task catalog TRANSFER_CONDO_INSURANCE — title |
| 496 | <code>Call your insurer 2-3 weeks ahead with the new address. Verify the new HOA master policy type — coverage needs may shift.</code> | Task catalog TRANSFER_CONDO_INSURANCE — desc |
| 498 | <code>1 min</code> | Task catalog TRANSFER_CONDO_INSURANCE — estPeezy |
| 499 | <code>Different HOAs = different coverage needs — re-quote, don't just transfer.</code> | Task catalog TRANSFER_CONDO_INSURANCE — tips |
| 501 | <code>An assumed transfer can leave gaps your old policy covered automatically.</code> | Task catalog TRANSFER_CONDO_INSURANCE — whyNeeded |
| 506 | <code>Transfer homeowner's insurance</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — title |
| 525 | <code>Call your insurer 3-4 weeks before closing. Premiums shift with location, age, square footage, and roof — get a new quote either way.</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — desc |
| 527 | <code>1 min</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — estPeezy |
| 528 | <code>Re-quote three insurers — transfers rarely beat fresh-quote pricing.</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — tips |
| 530 | <code>A 'transfer' often hides a premium increase you'd catch by shopping.</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — whyNeeded |
| 535 | <code>Transfer renter's insurance</code> | Task catalog TRANSFER_RENTERS_INSURANCE — title |
| 548 | <code>Call your insurer with the new address 1-2 weeks ahead. Transferring keeps your claims-free discount and skips the new policy fee.</code> | Task catalog TRANSFER_RENTERS_INSURANCE — desc |
| 550 | <code>1 min</code> | Task catalog TRANSFER_RENTERS_INSURANCE — estPeezy |
| 551 | <code>Ask for the multi-year loyalty discount — most insurers don't volunteer it.</code> | Task catalog TRANSFER_RENTERS_INSURANCE — tips |
| 553 | <code>Restarting fresh resets discounts you've spent years earning.</code> | Task catalog TRANSFER_RENTERS_INSURANCE — whyNeeded |
| 558 | <code>Scan your home</code> | Task catalog SCAN_INVENTORY — title |
| 566 | <code>Pan your camera slowly across each room. Peezy's AI identifies furniture, appliances, and large items in about 20 seconds per room.</code> | Task catalog SCAN_INVENTORY — desc |
| 568 | <code>90 secs</code> | Task catalog SCAN_INVENTORY — estPeezy |
| 569 | <code>Open closets and cabinets — Peezy catches what you'd forget to mention.</code> | Task catalog SCAN_INVENTORY — tips |
| 571 | <code>An accurate inventory unlocks precise quotes and protects you against damage claims.</code> | Task catalog SCAN_INVENTORY — whyNeeded |
| 575 | <code>Defrost your freezer</code> | Task catalog DEFROST_FREEZER — title |
| 582 | <code>Empty the contents, unplug it, prop the doors open, and lay towels underneath. Plan 24-48 hours before move day.</code> | Task catalog DEFROST_FREEZER — desc |
| 584 | <code>30 secs</code> | Task catalog DEFROST_FREEZER — estPeezy |
| 585 | <code>After moving, let it sit upright for 4 hours before plugging back in.</code> | Task catalog DEFROST_FREEZER — tips |
| 587 | <code>Movers won't load a wet or leaking fridge — full stop.</code> | Task catalog DEFROST_FREEZER — whyNeeded |
| 591 | <code>Deep clean the place</code> | Task catalog DIY_DEEP_CLEANING — title |
| 602 | <code>Plan 6+ hours with two people. Hit appliances, baseboards, walls, windows, vents, and cabinets — landlords inspect every one.</code> | Task catalog DIY_DEEP_CLEANING — desc |
| 604 | <code>30 secs</code> | Task catalog DIY_DEEP_CLEANING — estPeezy |
| 605 | <code>Clean inside the oven and fridge first — they're the top deduction trigger.</code> | Task catalog DIY_DEEP_CLEANING — tips |
| 607 | <code>One missed area can cost you hundreds in deposit deductions.</code> | Task catalog DIY_DEEP_CLEANING — whyNeeded |
| 611 | <code>Do the final touch-up</code> | Task catalog DIY_FINAL_CLEANING — title |
| 622 | <code>After everything is out, walk every room, closet, and cabinet. Wipe baseboards, sweep floors, and confirm nothing is left behind.</code> | Task catalog DIY_FINAL_CLEANING — desc |
| 624 | <code>30 secs</code> | Task catalog DIY_FINAL_CLEANING — estPeezy |
| 625 | <code>Bring a flashlight — corners and closets hide more than you think.</code> | Task catalog DIY_FINAL_CLEANING — tips |
| 627 | <code>A forgotten item or dusty corner is exactly what landlords cite.</code> | Task catalog DIY_FINAL_CLEANING — whyNeeded |
| 631 | <code>Cancel homeowner's insurance</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — title |
| 648 | <code>Call your insurer once the sale closes. Set the cancellation date for the day after closing — never before.</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — desc |
| 650 | <code>1 min</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — estPeezy |
| 651 | <code>Ask for the prepaid premium refund — most owe you for unused months.</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — tips |
| 653 | <code>Canceling early voids coverage during the final walkthrough and key transfer.</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — whyNeeded |
| 658 | <code>Update your license address</code> | Task catalog HANDLE_DMV_LOCAL — title |
| 669 | <code>Bring your current license and two proofs of new address to the DMV. Most states require updates within 30 days.</code> | Task catalog HANDLE_DMV_LOCAL — desc |
| 671 | <code>30 secs</code> | Task catalog HANDLE_DMV_LOCAL — estPeezy |
| 672 | <code>Check your state — many let you update online without an appointment.</code> | Task catalog HANDLE_DMV_LOCAL — tips |
| 674 | <code>An outdated address can void traffic ticket service and jury duty notices.</code> | Task catalog HANDLE_DMV_LOCAL — whyNeeded |
| 678 | <code>Handle the new-state DMV</code> | Task catalog HANDLE_DMV_INTERSTATE — title |
| 689 | <code>One DMV trip covers it: new license, and vehicle registration if you drive. Most states give you 30 days after the move.</code> | Task catalog HANDLE_DMV_INTERSTATE — desc |
| 691 | <code>30 secs</code> | Task catalog HANDLE_DMV_INTERSTATE — estPeezy |
| 692 | <code>Request REAL ID — TSA needs a new one in your new state.</code> | Task catalog HANDLE_DMV_INTERSTATE — tips |
| 694 | <code>Driving past the deadline on an out-of-state license is a moving violation.</code> | Task catalog HANDLE_DMV_INTERSTATE — whyNeeded |
| 703 | <code>Reserve move-out access</code> | Task catalog RESERVE_ACCESS_OLD — title |
| 715 | <code>Lock in truck parking — and the service elevator if your building has one — before move day.</code> | Task catalog RESERVE_ACCESS_OLD — desc |
| 717 | <code>1 min</code> | Task catalog RESERVE_ACCESS_OLD — estPeezy |
| 718 | <code>Reserve two adjacent spots — trucks need ramp clearance too.</code> | Task catalog RESERVE_ACCESS_OLD — tips |
| 720 | <code>No reserved access means movers burn paid hours hunting for parking.</code> | Task catalog RESERVE_ACCESS_OLD — whyNeeded |
| 738 | <code>Reserve move-in access</code> | Task catalog RESERVE_ACCESS_NEW — title |
| 750 | <code>Lock in truck parking at the new building — and the service elevator if there is one — before the truck arrives.</code> | Task catalog RESERVE_ACCESS_NEW — desc |
| 752 | <code>1 min</code> | Task catalog RESERVE_ACCESS_NEW — estPeezy |
| 753 | <code>Ask the building to cone off the spot the night before.</code> | Task catalog RESERVE_ACCESS_NEW — tips |
| 755 | <code>An unreserved elevator is the #1 cause of movers' overtime charges.</code> | Task catalog RESERVE_ACCESS_NEW — whyNeeded |
| 773 | <code>Protect your deposit</code> | Task catalog PROTECT_DEPOSIT — title |
| 784 | <code>Photograph the empty unit, return every key and fob, and keep the record — your deposit's evidence file.</code> | Task catalog PROTECT_DEPOSIT — desc |
| 786 | <code>30 secs</code> | Task catalog PROTECT_DEPOSIT — estPeezy |
| 787 | <code>Shoot video too — it captures context photos miss.</code> | Task catalog PROTECT_DEPOSIT — tips |
| 789 | <code>Without proof, deductions are your word against theirs.</code> | Task catalog PROTECT_DEPOSIT — whyNeeded |
| 793 | <code>Handle the school transfer</code> | Task catalog SCHOOL_TRANSFER — title |
| 807 | <code>Notify the current school, request records, and start enrollment at the new district — one parental job, one card.</code> | Task catalog SCHOOL_TRANSFER — desc |
| 809 | <code>1 min</code> | Task catalog SCHOOL_TRANSFER — estPeezy |
| 810 | <code>Many districts let you start enrollment paperwork online before you arrive.</code> | Task catalog SCHOOL_TRANSFER — tips |
| 812 | <code>Enrollment gaps cost kids school days.</code> | Task catalog SCHOOL_TRANSFER — whyNeeded |
| 816 | <code>Move your medical records</code> | Task catalog MEDICAL_RECORDS — title |
| 829 | <code>One pass across your providers — records requested, addresses updated, transfers started.</code> | Task catalog MEDICAL_RECORDS — desc |
| 831 | <code>1 min</code> | Task catalog MEDICAL_RECORDS — estPeezy |
| 832 | <code>Call the front desk — most offices send records electronically in days.</code> | Task catalog MEDICAL_RECORDS — tips |
| 834 | <code>New providers can't treat you safely without your history.</code> | Task catalog MEDICAL_RECORDS — whyNeeded |
| 848 | <code>Handle your money accounts</code> | Task catalog FINANCIAL_ACCOUNTS — title |
| 862 | <code>Banks, cards, brokerages, loans — one pass updates every address so autopay and statements never miss.</code> | Task catalog FINANCIAL_ACCOUNTS — desc |
| 864 | <code>1 min</code> | Task catalog FINANCIAL_ACCOUNTS — estPeezy |
| 865 | <code>Update before your next statement closes — mismatches trigger fraud alerts.</code> | Task catalog FINANCIAL_ACCOUNTS — tips |
| 867 | <code>Outdated info triggers fraud alerts and frozen cards on day one.</code> | Task catalog FINANCIAL_ACCOUNTS — whyNeeded |
| 882 | <code>Handle your memberships</code> | Task catalog MEMBERSHIPS — title |
| 897 | <code>Gyms, studios, spas, clubs — cancellations and transfers need 30-day notices. One pass, all of them.</code> | Task catalog MEMBERSHIPS — desc |
| 899 | <code>1 min</code> | Task catalog MEMBERSHIPS — estPeezy |
| 900 | <code>Check your membership terms — some require 30 days written notice.</code> | Task catalog MEMBERSHIPS — tips |
| 902 | <code>Miss a notice window and you pay for a gym you can't visit.</code> | Task catalog MEMBERSHIPS — whyNeeded |
| 918 | <code>Line up your storage unit</code> | Task catalog STORAGE_UNIT — title |
| 929 | <code>We'll find units near your new place with real availability and move-in specials before move day.</code> | Task catalog STORAGE_UNIT — desc |
| 931 | <code>1 min</code> | Task catalog STORAGE_UNIT — estPeezy |
| 932 | <code>Book two weeks out — first-month-free deals go to early reservations.</code> | Task catalog STORAGE_UNIT — tips |
| 934 | <code>Sold-out units near the new place mean storing across town.</code> | Task catalog STORAGE_UNIT — whyNeeded |
| 938 | <code>Add your new address</code> | Task catalog ADD_NEW_ADDRESS — title |
| 949 | <code>Your plan is waiting on the destination. Add it and everything downstream unlocks.</code> | Task catalog ADD_NEW_ADDRESS — desc |
| 951 | <code>30 secs</code> | Task catalog ADD_NEW_ADDRESS — estPeezy |
| 952 | <code>A street address beats a city — distance and deadlines get exact.</code> | Task catalog ADD_NEW_ADDRESS — tips |
| 954 | <code>Distance, deadlines, and half your tasks depend on where you're headed.</code> | Task catalog ADD_NEW_ADDRESS — whyNeeded |
| 958 | <code>Lock in your move date</code> | Task catalog CONFIRM_MOVE_DATE — title |
| 969 | <code>You marked the date flexible. Lock it in — or confirm the estimate — so the plan paces itself right.</code> | Task catalog CONFIRM_MOVE_DATE — desc |
| 971 | <code>30 secs</code> | Task catalog CONFIRM_MOVE_DATE — estPeezy |
| 972 | <code>Mid-month weekdays book cheaper movers than month-end weekends.</code> | Task catalog CONFIRM_MOVE_DATE — tips |
| 974 | <code>Every deadline on your plan counts backward from this date.</code> | Task catalog CONFIRM_MOVE_DATE — whyNeeded |
| 978 | <code>Lighten the load?</code> | Task catalog DECLUTTER_INTENT — title |
| 990 | <code>One tap: planning to sell or donate before the move? We'll line up the right help.</code> | Task catalog DECLUTTER_INTENT — desc |
| 992 | <code>10 secs</code> | Task catalog DECLUTTER_INTENT — estPeezy |
| 993 | <code>Every unsold item becomes a box you pay to move.</code> | Task catalog DECLUTTER_INTENT — tips |
| 995 | <code>Selling and donating both need lead time — the earlier we know, the more it pays.</code> | Task catalog DECLUTTER_INTENT — whyNeeded |
| 999 | <code>Need a storage unit?</code> | Task catalog STORAGE_NEED — title |
| 1011 | <code>Will everything fit — or might you need a unit? One tap and we'll handle the rest.</code> | Task catalog STORAGE_NEED — desc |
| 1013 | <code>10 secs</code> | Task catalog STORAGE_NEED — estPeezy |
| 1014 | <code>Units near new builds sell out first — early answers get options.</code> | Task catalog STORAGE_NEED — tips |
| 1016 | <code>Storage found on move day costs double and sits across town.</code> | Task catalog STORAGE_NEED — whyNeeded |
| 1020 | <code>Tell us how moving day went</code> | Task catalog MOVE_CHECKIN — title |
| 1029 | <code>Four factual questions help Peezy hold moving partners accountable and improve the experience for everyone.</code> | Task catalog MOVE_CHECKIN — desc |
| 1031 | <code>1 min</code> | Task catalog MOVE_CHECKIN — estPeezy |
| 1032 | <code>Stick to what happened — arrival, pace, price, and damage.</code> | Task catalog MOVE_CHECKIN — tips |
| 1034 | <code>Fresh facts are how good vendors earn trust and bad behavior gets addressed.</code> | Task catalog MOVE_CHECKIN — whyNeeded |
| 1038 | <code>Return or recycle your boxes</code> | Task catalog BOX_RETURN — title |
| 1047 | <code>Count the boxes leaving your home so Peezy can tune future kits and help arrange pickup if you want it.</code> | Task catalog BOX_RETURN — desc |
| 1049 | <code>30 secs</code> | Task catalog BOX_RETURN — estPeezy |
| 1050 | <code>Flatten clean boxes before recycling or pickup.</code> | Task catalog BOX_RETURN — tips |
| 1052 | <code>Returned counts reduce waste and make the next kit estimate sharper.</code> | Task catalog BOX_RETURN — whyNeeded |

### `functions/validateSubscription.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 23 | <code>Method not allowed</code> | HTTP error payload |
| 39 | <code>Missing required fields</code> | HTTP error payload |
| 86 | <code>Sync failed</code> | HTTP error payload |
