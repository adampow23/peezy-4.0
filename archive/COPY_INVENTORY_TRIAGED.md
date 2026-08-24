# Peezy copy inventory — prose triage

Triaged from `COPY_INVENTORY.md`. No source copy was rewritten.

## Coverage

- 750 entries a user reads as prose.
- Included: sentence-like questions and question context, helper/subtext, empty states, confirmations and dialog bodies, consequence/status lines, onboarding/explainer-adjacent text, and actionable user errors.
- Excluded: button and option labels, standard iOS-pattern strings, terse field placeholders, accessibility copy, implementation/debug/log text, values/fragments, non-actionable internal errors, and every LOCKED entry.
- Source file, current 1-based line, exact current text, and screen/runtime context are preserved from the source inventory.

## iOS runtime strings

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

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AssessmentIntroView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 18 | <code>Welcome to the easy part</code> | AssessmentIntroView — heading/title |
| 19 | <code>You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move.</code> | AssessmentIntroView — generated/display copy |
| 55 | <code>Just a quick 90 second setup</code> | AssessmentIntroView — screen text |

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

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/ReadyView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 56 | <code>Your task list is ready</code> | ReadyView — screen text |
| 60 | <code>We've organized everything you need for a smooth move.</code> | ReadyView — screen text |

### `Peezy 4.0/Assessment/AssessmentViews/Onboarding/SummaryView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 46 | <code>Here's what we built for you</code> | SummaryView — screen text |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/Addresschangeintro.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 10 | <code>Time to make sure everyone knows where to find you.</code> | AddressChangeIntro — heading/title |
| 11 | <code>You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider, we've got you covered.</code> | AddressChangeIntro — helper/subtext |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentAddress.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>What's the current address?</code> | CurrentAddress — heading/title |
| 10 | <code>I'll use this for mail forwarding, utilities, and more.</code> | CurrentAddress — helper/subtext |
| 11 | <code>Start typing your address</code> | CurrentAddress — field placeholder/helper |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/FinancialInstitutions.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>Let's start with finance related accounts you might have.</code> | FinancialInstitutions — heading/title |
| 6 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | FinancialInstitutions — helper/subtext |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/FitnessWellness.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>And lastly, do you have any wellness-related memberships?</code> | FitnessWellness — heading/title |
| 6 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | FitnessWellness — helper/subtext |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/HealthcareProviders.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 5 | <code>Now for any health-related accounts?</code> | HealthcareProviders — heading/title |
| 6 | <code>Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you.</code> | HealthcareProviders — helper/subtext |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDate.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>When's the big day?</code> | MoveDate — heading/title |
| 10 | <code>If you're unsure, put your best guess and you can update it later.</code> | MoveDate — helper/subtext |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/NewAddress.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>What's the new address?</code> | NewAddress — heading/title |
| 10 | <code>I'll use this to get utilities, internet, and everything else set up before you walk in.</code> | NewAddress — helper/subtext |
| 11 | <code>Start typing your address</code> | NewAddress — field placeholder/helper |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/Servicesintro.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 10 | <code>Time to talk services.</code> | ServicesIntro — heading/title |
| 11 | <code>We'll ask about services you might want help with — movers, packers, cleaners, and more.</code> | ServicesIntro — helper/subtext |

### `Peezy 4.0/Assessment/AssessmentViews/Questions/UserName.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 9 | <code>What's your first name?</code> | UserName — heading/title |

### `Peezy 4.0/Auth/AuthView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 45 | <code>Moving made peezy.</code> | AuthLoadingState — generated/display copy |
| 45 | <code>Your move, on autopilot.</code> | AuthLoadingState — generated/display copy |
| 132 | <code>Already have an account?</code> | AuthLoadingState — screen text |

### `Peezy 4.0/Auth/LogInView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 47 | <code>Log in to continue your move</code> | LoginView — screen text |
| 90 | <code>Please enter your email address first</code> | LoginView — error message |
| 96 | <code>Forgot password?</code> | LoginView — alert/confirmation |
| 108 | <code>Don't have an account?</code> | LoginView — screen text |
| 143 | <code>Password reset email sent to \(email)</code> | LoginView — error message |
| 150 | <code>Send a password reset email to \(email)?</code> | LoginView — alert/confirmation |
| 152 | <code>Email sent</code> | LoginView — alert/confirmation |

### `Peezy 4.0/Auth/SignUpView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 46 | <code>Sign up to get started with Peezy</code> | SignUpView — screen text |
| 66 | <code>Min. 6 characters</code> | SignUpView — field placeholder/helper |
| 84 | <code>Passwords do not match</code> | SignUpView — error message |
| 109 | <code>Already have an account?</code> | SignUpView — screen text |
| 142 | <code>Passwords do not match</code> | SignUpView — error message |

### `Peezy 4.0/Inventory/Models/InventorySessionManager.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 277 | <code>Couldn't save that coverage answer. Please try again.</code> | is — error message |
| 286 | <code>You must be signed in to scan inventory</code> | is — error message |
| 297 | <code>Uploading frames...</code> | is — generated/display copy |
| 329 | <code>Analyzing room...</code> | is — generated/display copy |
| 425 | <code>Analyzing room...</code> | is — generated/display copy |

### `Peezy 4.0/Inventory/Services/InventoryAPIClient.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 71 | <code>You must be signed in to scan inventory</code> | InventoryError — error message |
| 73 | <code>Processing failed: \(msg)</code> | InventoryError — error message |
| 74 | <code>Network error: \(err.localizedDescription)</code> | InventoryError — error message |
| 75 | <code>Upload failed: \(msg)</code> | InventoryError — error message |

### `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 249 | <code>No camera available on this device</code> | CaptureError — error message |

### `Peezy 4.0/Inventory/Views/InventoryCameraView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 30 | <code>Peezy AI is scanning...</code> | InventoryCameraView — generated/display copy |
| 31 | <code>Identifying items...</code> | InventoryCameraView — generated/display copy |
| 32 | <code>Keep panning slowly...</code> | InventoryCameraView — generated/display copy |
| 140 | <code>Camera access needed</code> | InventoryCameraView — screen text |
| 144 | <code>Peezy uses your camera to scan rooms and identify what you're moving. You can enable access in iOS Settings.</code> | InventoryCameraView — screen text |
| 370 | <code>Pan slowly around the room</code> | InventoryCameraView — screen text |
| 414 | <code>Processing frames...</code> | InventoryCameraView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryFlowView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 148 | <code>Submitted!</code> | InventoryFlowView — alert/confirmation |
| 155 | <code>Your inventory has been submitted. We'll use it to coordinate your move.</code> | InventoryFlowView — screen text |
| 227 | <code>Here's how it works</code> | InventoryFlowView — heading/title |
| 228 | <code>Pan your camera slowly around each room — about 20 seconds per room. Peezy uses AI (Anthropic Claude) to identify furniture and belongings automatically.\n\nOpen closets and cabinets. Go one room at a time for the best results.\n\nYour scan video frames are sent securely to Anthropic for processing and are not stored or used for AI training. See our Privacy Policy at peezy-1ecrdl.web.app/privacy.html for details.</code> | InventoryFlowView — generated/display copy |
| 274 | <code>Room saved!</code> | InventoryFlowView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryItemConfirmView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 87 | <code>Help us identify a few items</code> | InventoryItemConfirmView — screen text |
| 103 | <code>What is this item?</code> | InventoryItemConfirmView — field placeholder/helper |
| 119 | <code>Is this a **\(item.name)**?</code> | InventoryItemConfirmView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryLockedView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 42 | <code>Inventory submitted</code> | InventoryLockedView — screen text |
| 50 | <code>Need to make a change? Send us a message in the chat and we'll update it for you.</code> | InventoryLockedView — screen text |

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
| 83 | <code>Remove \(room.name) and its \(room.items.count) items?</code> | InventoryRoomHubView — screen text |
| 86 | <code>Ready to submit?</code> | InventoryRoomHubView — alert/confirmation |
| 92 | <code>Are you sure you've scanned all your rooms? Once submitted, you won't be able to add or change rooms. If something changes, message us in the chat.</code> | InventoryRoomHubView — screen text |
| 130 | <code>Scan your first room to start\nbuilding your inventory</code> | InventoryRoomHubView — screen text |
| 162 | <code>Scanned: \(report.scannedRoomNames.joined(separator: ", "))</code> | InventoryRoomHubView — screen text |
| 173 | <code>Not seen: \(report.unresolvedRooms.map(\.displayName).joined(separator: ", "))</code> | InventoryRoomHubView — screen text |
| 339 | <code>What room are you scanning?</code> | InventoryRoomHubView — screen text |

### `Peezy 4.0/Inventory/Views/InventoryRoomReviewView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 44 | <code>What item are you adding?</code> | AddItemQuestion — generated/display copy |
| 45 | <code>What kind of item is it?</code> | AddItemQuestion — generated/display copy |
| 46 | <code>Which category fits best?</code> | AddItemQuestion — generated/display copy |
| 47 | <code>What size is it?</code> | AddItemQuestion — generated/display copy |
| 99 | <code>Are you sure you're not moving this?</code> | AddItemQuestion — alert/confirmation |
| 105 | <code>\(item.name) removed</code> | AddItemQuestion — generated/display copy |
| 109 | <code>\(item.name) will be removed from your inventory.</code> | AddItemQuestion — screen text |

### `Peezy 4.0/MainInterface/Models/BoxReturnService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
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
| 100 | <code>No internet plans are available right now.</code> | ISPPlanError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 24 | <code>A custom quote for the long haul</code> | MoversConciergeReason — heading/title |
| 25 | <code>Long-distance moves get a hand-built quote from us — you'll have it within a day.</code> | MoversConciergeReason — generated/display copy |
| 29 | <code>This is a big one.</code> | MoversConciergeReason — heading/title |
| 30 | <code>Big moves deserve a hand-built quote — we'll have yours within a day.</code> | MoversConciergeReason — generated/display copy |
| 115 | <code>Sign in again to continue booking your movers.</code> | MoversFlowViewModel — generated/display copy |
| 121 | <code>Your move details are missing. Add both addresses in Settings, then try again.</code> | MoversFlowViewModel — generated/display copy |
| 146 | <code>The scan finished without any move items. Try the scan again or use home details.</code> | MoversFlowViewModel — generated/display copy |
| 368 | <code>We couldn't send the booking request. Nothing was booked—please try again. \(error.localizedDescription)</code> | MoversFlowViewModel — error message |
| 403 | <code>We couldn't send the quote request. Nothing was submitted—please try again. \(error.localizedDescription)</code> | MoversFlowViewModel — error message |
| 616 | <code>Your identity details could not be loaded.</code> | FlowError — error message |
| 617 | <code>Your move scope could not be calculated.</code> | FlowError — generated/display copy |
| 618 | <code>Add your current address before comparing movers.</code> | FlowError — generated/display copy |
| 619 | <code>We couldn't verify which movers serve your current address.</code> | FlowError — generated/display copy |
| 620 | <code>No active movers currently cover this address.</code> | FlowError — generated/display copy |
| 621 | <code>The booking service did not accept the request.</code> | FlowError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PackingConstants.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 39 | <code>Medications, chargers, toiletries, clothes, and move-day documents</code> | PackingConstants — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PackingPlanEngine.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 237 | <code>\(completedSession.roomLabel) done — \(completedRooms.count) of \(roomNames.count) rooms packed. On pace for \(moveDate).</code> | WorkUnit — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PeezyClient.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 238 | <code>Network error: \(error.localizedDescription)</code> | PeezyError — error message |

### `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 130 | <code>You're all caught up for today!</code> | HomeState — generated/display copy |
| 132 | <code>Just \(dailyTarget) \(taskWord) to knock out today!</code> | HomeState — generated/display copy |
| 138 | <code>You're all caught up for today!</code> | HomeState — generated/display copy |
| 139 | <code>You've knocked out all \(dailyTarget) for today!</code> | HomeState — generated/display copy |
| 141 | <code>You've done \(completed) of \(dailyTarget) today — \(remaining) \(taskWord) to go.</code> | HomeState — generated/display copy |
| 146 | <code>Welcome back, \(name)!</code> | HomeState — generated/display copy |

### `Peezy 4.0/MainInterface/Models/PricingEngine.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 301 | <code>Sized so your move wraps in one solid morning — not a marathon.</code> | PricingEngine — generated/display copy |
| 359 | <code>Includes what scans can't see — closets, cabinets, drawers.</code> | PricingEngine — generated/display copy |
| 374 | <code>Some rooms weren't scanned.</code> | PricingEngine — generated/display copy |
| 377 | <code>Storage stop estimated — add the unit's address to tighten this.</code> | PricingEngine — generated/display copy |
| 391 | <code>Includes \(item.handlingLabel) handling</code> | PricingEngine — generated/display copy |

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
| 650 | <code>Confirm packing, furniture, building access, a clear path, and your first-night bag.</code> | TaskActionService — generated/display copy |
| 657 | <code>Tap each item as it becomes ready. Nothing here blocks your move.</code> | TaskActionService — generated/display copy |
| 658 | <code>A final readiness record protects the estimate and explains avoidable overages.</code> | TaskActionService — generated/display copy |
| 724 | <code>The right supplies arrive before packing starts, without a mid-session store run.</code> | TaskActionService — generated/display copy |
| 820 | <code>A signed-in user is required to create a packing plan.</code> | PackingPlanPersistenceError — error message |
| 821 | <code>Add a move date before creating a packing plan.</code> | PackingPlanPersistenceError — generated/display copy |
| 822 | <code>That packing session is no longer available.</code> | PackingPlanPersistenceError — generated/display copy |
| 823 | <code>That packing supplies kit is no longer available.</code> | PackingPlanPersistenceError — generated/display copy |
| 824 | <code>That moving-day readiness check is no longer available.</code> | PackingPlanPersistenceError — generated/display copy |

### `Peezy 4.0/MainInterface/Models/WorkflowService.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 84 | <code>Failed to submit answers: \(message)</code> | WorkflowServiceError — generated/display copy |

### `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 52 | <code>Let us handle the\nheavy lifting.</code> | PaywallGateView — screen text |
| 58 | <code>Moving costs the average person 25+ hours of stress. Upgrade to Peezy+ and get:</code> | PaywallGateView — screen text |
| 67 | <code>Personalized moving plan built from your assessment</code> | PaywallGateView — generated/display copy |
| 68 | <code>Most tasks, done for you. The rest, walked through step-by-step</code> | PaywallGateView — generated/display copy |
| 69 | <code>AI inventory scanner for every room</code> | PaywallGateView — generated/display copy |
| 70 | <code>Daily task stream so nothing slips through the cracks</code> | PaywallGateView — generated/display copy |
| 71 | <code>Priority support via in-app chat</code> | PaywallGateView — generated/display copy |
| 72 | <code>Plan updates as your move evolves</code> | PaywallGateView — generated/display copy |
| 129 | <code>Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings &gt; Apple ID &gt; Subscriptions.</code> | PaywallGateView — alert/confirmation |

### `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 231 | <code>Stay in control.</code> | PeezyHomeView — generated/display copy |
| 232 | <code>We're here to help.</code> | PeezyHomeView — generated/display copy |
| 242 | <code>Just \(daily) \(taskWord) per day to stay on pace.\n\nCheck in once a day, knock them out, and you're set.</code> | PeezyHomeView — generated/display copy |
| 244 | <code>Check in once a day, complete your daily tasks, and you'll be on pace to get everything done.</code> | PeezyHomeView — generated/display copy |
| 247 | <code>Your full task list is in the Tasks tab below.\n\nNeed to update move details? Head to Settings. Questions or feedback? Use the Chat tab.</code> | PeezyHomeView — generated/display copy |
| 249 | <code>Need help with a task? Tap it to learn more, or head to Settings to contact support.</code> | PeezyHomeView — generated/display copy |
| 348 | <code>Loading your task...</code> | PeezyHomeView — screen text |

### `Peezy 4.0/MainInterface/Views/ProviderActionCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 43 | <code>Hi, I'm calling to update the address on my account to my new address.</code> | ProviderActionKind — generated/display copy |
| 45 | <code>Hi, I'm calling to cancel my membership. Please confirm the effective date and any final charge.</code> | ProviderActionKind — generated/display copy |
| 47 | <code>Hi, I'm calling to transfer my membership to a location near my new address.</code> | ProviderActionKind — generated/display copy |
| 49 | <code>Hi, I'm calling to transfer my records to a new provider. What do you need from me?</code> | ProviderActionKind — generated/display copy |
| 51 | <code>Hi, I'm calling to close my account. Please confirm the effective date and any final balance.</code> | ProviderActionKind — generated/display copy |
| 115 | <code>Copied your details.</code> | ProviderActionCard — generated/display copy |
| 129 | <code>Add your name and new address in Settings to copy them here.</code> | ProviderActionCard — screen text |
| 273 | <code>We'll take it from here</code> | ProviderActionCard — generated/display copy |
| 342 | <code>Checking \(providerName)…</code> | ProviderResolutionLoadingCard — generated/display copy |

### `Peezy 4.0/MainInterface/Views/Shared/HomeBackgroundComponents.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>Loading your tasks...</code> | LoadingView — screen text |

### `Peezy 4.0/MainInterface/Views/SupportChatView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 50 | <code>We typically respond within a few hours</code> | SupportChatView — screen text |
| 68 | <code>Ask about your tasks, your move, or anything we can help with. We usually respond within a few hours.</code> | SupportChatView — screen text |
| 152 | <code>What can we help with?</code> | SupportChatView — field placeholder/helper |

### `Peezy 4.0/Menu/PeezySettingsView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 157 | <code>Move date updated</code> | PeezySettingsView — generated/display copy |
| 164 | <code>Current address updated</code> | PeezySettingsView — generated/display copy |
| 171 | <code>New address updated</code> | PeezySettingsView — generated/display copy |
| 177 | <code>Profile updated</code> | PeezySettingsView — generated/display copy |
| 180 | <code>Retake Assessment?</code> | PeezySettingsView — alert/confirmation |
| 186 | <code>This will reset your tasks and personalized plan. Your account will not be affected.</code> | PeezySettingsView — alert/confirmation |
| 188 | <code>Sign Out?</code> | PeezySettingsView — alert/confirmation |
| 194 | <code>You'll need to sign back in to access your tasks.</code> | PeezySettingsView — alert/confirmation |
| 196 | <code>Delete Account?</code> | PeezySettingsView — alert/confirmation |
| 202 | <code>This will permanently delete your account, all your tasks, and all your data. This cannot be undone.\n\nIf you have an active subscription, please cancel it first in your Apple ID settings.</code> | PeezySettingsView — error message |
| 382 | <code>Purchases restored successfully.</code> | PeezySettingsView — error message |
| 384 | <code>Unable to restore purchases. Please try again.</code> | PeezySettingsView — generated/display copy |
| 637 | <code>Resetting your data...</code> | PeezySettingsView — generated/display copy |
| 673 | <code>Failed to reset: \(error.localizedDescription)</code> | PeezySettingsView — error message |
| 683 | <code>Deleting your account...</code> | PeezySettingsView — generated/display copy |
| 705 | <code>Account deletion failed. Please try again or contact support.</code> | PeezySettingsView — error message |
| 810 | <code>Failed to save: \(error.localizedDescription)</code> | EditedAddressKind — error message |
| 844 | <code>Failed to save: \(error.localizedDescription)</code> | EditedAddressKind — error message |
| 904 | <code>Update Move Date?</code> | EditMoveDateSheet — alert/confirmation |
| 911 | <code>This will update your tasks and timeline to reflect the new date.</code> | EditMoveDateSheet — screen text |
| 1149 | <code>Not signed in</code> | EditNameEmailSheet — error message |
| 1181 | <code>Save failed: \(error.localizedDescription)</code> | EditNameEmailSheet — error message |

### `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 172 | <code>Would you like us to take care of this for you?</code> | FlowEngineView — generated/display copy |
| 256 | <code>Is this your move date?</code> | FlowEngineView — generated/display copy |
| 640 | <code>This one isn't quite ready in the app — we're on it. It'll stay on your list.</code> | ComingRightUpCard — screen text |

### `Peezy 4.0/Tasks/FlowEngine/InAppTaskFlows.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 174 | <code>Couldn't save the address — please try again</code> | AddNewAddressFlow — error message |
| 205 | <code>Is this the real date?</code> | ConfirmMoveDateFlow — generated/display copy |
| 246 | <code>Couldn't save the date — please try again</code> | ConfirmMoveDateFlow — error message |
| 319 | <code>Couldn't save — please try again</code> | DeclutterIntentFlow — error message |
| 388 | <code>Couldn't save — please try again</code> | StorageNeedFlow — error message |

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
| 156 | <code>No memo to display</code> | AdminMemoFlow — error message |
| 170 | <code>Memo not found</code> | AdminMemoFlow — error message |
| 181 | <code>No content in this memo</code> | AdminMemoFlow — error message |
| 188 | <code>Failed to load memo</code> | AdminMemoFlow — error message |

### `Peezy 4.0/Tasks/Task Card Components/QuoteSelectionFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 52 | <code>Loading quotes...</code> | QuoteSelectionFlow — screen text |
| 132 | <code>Pick the one that\nworks for you</code> | QuoteSelectionFlow — screen text |
| 142 | <code>Tap an option to select it. You can always change your mind.</code> | QuoteSelectionFlow — screen text |
| 248 | <code>Great choice</code> | QuoteSelectionFlow — screen text |
| 276 | <code>We'll reach out to them and get everything set up for you.</code> | QuoteSelectionFlow — screen text |
| 314 | <code>Quote not found</code> | QuoteSelectionFlow — error message |
| 340 | <code>No quote options found</code> | QuoteSelectionFlow — error message |
| 351 | <code>Failed to load quotes</code> | QuoteSelectionFlow — error message |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowDecisionCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 17 | <code>Would you like us to take care of this for you?</code> | TaskFlowDecisionCard — generated/display copy |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowStatusCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>What's the plan with this?</code> | TaskFlowStatusCard — generated/display copy |

### `Peezy 4.0/Tasks/Task Card Components/TaskFlowSummaryCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 43 | <code>Eezy Peezy!</code> | TaskFlowSummaryCard — screen text |

### `Peezy 4.0/Tasks/Task Cards/BoxReturnView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 94 | <code>Finding your packing kit…</code> | BoxReturnQuestion — error message |
| 156 | <code>How many boxes are you returning or recycling?</code> | BoxReturnQuestion — screen text |
| 161 | <code>Your kit included \(delivered) boxes. The count helps us size future kits with less waste.</code> | BoxReturnQuestion — screen text |
| 185 | <code>Did you run out of boxes before move day?</code> | BoxReturnQuestion — screen text |
| 196 | <code>Would you like Peezy to arrange pickup?</code> | BoxReturnQuestion — screen text |
| 207 | <code>We'll send the count to the concierge team and follow up about pickup.</code> | BoxReturnQuestion — screen text |
| 233 | <code>Got it — \(calibration.returned) of \(calibration.delivered) boxes recorded.</code> | BoxReturnQuestion — screen text |
| 239 | <code>Your pickup request is with the concierge team.</code> | BoxReturnQuestion — screen text |

### `Peezy 4.0/Tasks/Task Cards/FindCleanersFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 120 | <code>Which place needs cleaning?</code> | FindCleanersFlow — generated/display copy |
| 134 | <code>What services do you need?</code> | FindCleanersFlow — generated/display copy |
| 150 | <code>When do you need the move-out clean?</code> | FindCleanersFlow — generated/display copy |
| 165 | <code>When do you need the move-in clean?</code> | FindCleanersFlow — generated/display copy |
| 180 | <code>We'll find cleaners who can handle everything you selected and get you quotes.</code> | FindCleanersFlow — generated/display copy |
| 181 | <code>Response times are typically 24–48 hours.</code> | FindCleanersFlow — helper/subtext |

### `Peezy 4.0/Tasks/Task Cards/FindMoversFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 81 | <code>Preparing your move scope…</code> | FindMoversFlow — generated/display copy |
| 149 | <code>An unexpected error occurred.</code> | FindMoversFlow — error message |
| 182 | <code>Your quote request is in</code> | FindMoversFlow — screen text |
| 186 | <code>We'll follow up with your hand-built mover quote within a day.</code> | FindMoversFlow — screen text |
| 241 | <code>Anything we should know?</code> | MoversConciergeQuoteCard — field placeholder/helper |

### `Peezy 4.0/Tasks/Task Cards/HandleAutoInsuranceFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 211 | <code>How would you like to handle this?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 224 | <code>What would you like to do?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 258 | <code>Who's your current provider?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 272 | <code>We'll reach out to \(providerName) and get your address updated.</code> | HandleAutoInsuranceFlow — generated/display copy |
| 273 | <code>Response times are typically 24–48 hours.</code> | HandleAutoInsuranceFlow — helper/subtext |
| 287 | <code>Who do you have it with now?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 303 | <code>Would you like to stay with \(providerName), or get quotes from others too?</code> | HandleAutoInsuranceFlow — generated/display copy |
| 317 | <code>Response times are typically 24–48 hours.</code> | HandleAutoInsuranceFlow — helper/subtext |
| 332 | <code>Most states require auto insurance to legally drive. If you're getting a car at your new place, you'll need a policy before registration.</code> | HandleAutoInsuranceFlow — generated/display copy |
| 359 | <code>Here's what to tell your agent: your new address, your move date, and whether your housing type is changing. Ask them to confirm your new rate before the move — rates change by zip code.</code> | HandleAutoInsuranceFlow — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/HandleHomeInsuranceFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 210 | <code>How would you like to handle this?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 223 | <code>What would you like to do?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 257 | <code>Who's your current provider?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 271 | <code>We'll reach out to \(providerName) and get your address updated.</code> | HandleHomeInsuranceFlow — generated/display copy |
| 272 | <code>Response times are typically 24–48 hours.</code> | HandleHomeInsuranceFlow — helper/subtext |
| 286 | <code>Who do you have it with now?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 302 | <code>Would you like to stay with \(providerName), or get quotes from others too?</code> | HandleHomeInsuranceFlow — generated/display copy |
| 316 | <code>Response times are typically 24–48 hours.</code> | HandleHomeInsuranceFlow — helper/subtext |
| 331 | <code>If you're renting, most leases require renter's insurance — it's usually $15-25/month and protects your stuff. If you're buying, your lender requires homeowner's insurance before closing.</code> | HandleHomeInsuranceFlow — generated/display copy |
| 358 | <code>Here's what to tell your agent: your new address, your move date, and whether your housing type is changing. Ask them to confirm your new rate before the move — rates change by zip code.</code> | HandleHomeInsuranceFlow — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/MoveCheckInView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 131 | <code>Loading your moving-day check-in…</code> | CheckInQuestion — error message |
| 191 | <code>Did they arrive in the window?</code> | CheckInQuestion — generated/display copy |
| 200 | <code>Did the crew work steadily?</code> | CheckInQuestion — generated/display copy |
| 209 | <code>Did anything cost more than quoted?</code> | CheckInQuestion — generated/display copy |
| 218 | <code>Was anything damaged?</code> | CheckInQuestion — generated/display copy |
| 227 | <code>Anything else we should know?</code> | CheckInQuestion — screen text |
| 238 | <code>What was the final bill?</code> | CheckInQuestion — screen text |
| 255 | <code>Enter a final bill greater than $0, or leave it blank.</code> | CheckInQuestion — screen text |
| 288 | <code>Thanks. We saved the facts and we'll follow up on anything that needs attention.</code> | CheckInQuestion — screen text |

### `Peezy 4.0/Tasks/Task Cards/MoveRefinementView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
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
| 196 | <code>Example: 8–10 AM</code> | Question — field placeholder/helper |

### `Peezy 4.0/Tasks/Task Cards/MoversBookingReviewView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 35 | <code>Anything the company should know?</code> | MoversBookingReviewView — field placeholder/helper |

### `Peezy 4.0/Tasks/Task Cards/MoversCaptureCard.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 25 | <code>First, let's measure the move</code> | MoversCaptureCard — screen text |
| 30 | <code>A room-by-room scan gives every company the same scope. If video isn't an option, home details still produce a wider estimate range.</code> | MoversCaptureCard — screen text |

### `Peezy 4.0/Tasks/Task Cards/MoversComparisonView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 21 | <code>Same scope. Three prices.</code> | MoversComparisonView — screen text |
| 25 | <code>Ordered by estimated total.</code> | MoversComparisonView — screen text |

### `Peezy 4.0/Tasks/Task Cards/MoversConfirmationView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 24 | <code>Request sent to \(vendorName)</code> | MoversConfirmationView — screen text |
| 29 | <code>Same price basis for every mover. If anything changes day-of, that's on them — and on us.</code> | MoversConfirmationView — screen text |
| 34 | <code>We'll confirm the requested window and next steps as soon as the company responds.</code> | MoversConfirmationView — screen text |

### `Peezy 4.0/Tasks/Task Cards/MoveScopeSummaryView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 24 | <code>Here's the scope we're pricing</code> | MoveScopeSummaryView — screen text |

### `Peezy 4.0/Tasks/Task Cards/PackingReadinessView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 58 | <code>Loading your readiness check…</code> | PackingReadinessView — error message |
| 75 | <code>One last readiness check</code> | PackingReadinessView — screen text |
| 81 | <code>Set for \(record.scheduledDate.formatted(date: .abbreviated, time: .omitted)) — the day before your move.</code> | PackingReadinessView — screen text |

### `Peezy 4.0/Tasks/Task Cards/PackingSessionView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 48 | <code>Loading today's session…</code> | PackingSessionView — error message |
| 66 | <code>Today: \(session.roomLabel). About \(session.estMinutes) minutes.</code> | PackingSessionView — screen text |
| 73 | <code>Here's what's in it</code> | PackingSessionView — screen text |

### `Peezy 4.0/Tasks/Task Cards/RemoveItemsFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 77 | <code>What are you looking to do with these items?</code> | RemoveItemsFlow — generated/display copy |
| 91 | <code>What types of items are we talking about?</code> | RemoveItemsFlow — generated/display copy |
| 109 | <code>What condition are most of the items in?</code> | RemoveItemsFlow — generated/display copy |
| 124 | <code>How much stuff are we talking about?</code> | RemoveItemsFlow — generated/display copy |
| 139 | <code>Where are the items right now?</code> | RemoveItemsFlow — generated/display copy |
| 154 | <code>Do you need them picked up, or can you drop them off?</code> | RemoveItemsFlow — generated/display copy |
| 168 | <code>We'll find the best option for your items and get it scheduled.</code> | RemoveItemsFlow — generated/display copy |
| 169 | <code>Response times are typically 24–48 hours.</code> | RemoveItemsFlow — helper/subtext |

### `Peezy 4.0/Tasks/Task Cards/RentTruckFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 52 | <code>What type of rental?</code> | RentTruckFlow — generated/display copy |

### `Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 76 | <code>What types of items are you selling?</code> | SellItemsFlow — generated/display copy |
| 93 | <code>Roughly, what do you think everything is worth?</code> | SellItemsFlow — generated/display copy |
| 108 | <code>Which platforms are you open to?</code> | SellItemsFlow — generated/display copy |
| 125 | <code>We'll put together a selling plan based on what you've got and where to list it.</code> | SellItemsFlow — generated/display copy |
| 126 | <code>Response times are typically 24–48 hours.</code> | SellItemsFlow — helper/subtext |

### `Peezy 4.0/Tasks/Task Cards/SetupInternetFlow.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 205 | <code>We couldn't load internet plans. Check your connection and try again.</code> | SetupInternetFlow — error message |
| 218 | <code>We couldn't load internet plans. Check your connection and try again.</code> | SetupInternetFlow — error message |

### `Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 81 | <code>Building your kit…</code> | SuppliesKitView — error message |
| 104 | <code>Sized from your home scan</code> | SuppliesKitView — screen text |
| 131 | <code>Deliver by \(deliveryBy.formatted(date: .abbreviated, time: .omitted)) — before your first packing session.</code> | SuppliesKitView — screen text |
| 201 | <code>Kit request sent. Peezy is lining up the supplies before packing starts.</code> | SuppliesKitView — screen text |
| 444 | <code>Your move profile is missing. Add it in Settings before ordering the kit.</code> | SuppliesKitSubmissionError — error message |
| 508 | <code>How many \(currentField.label.lowercased()) do you want?</code> | KitField — screen text |

### `Peezy 4.0/Tasks/Views/PendingConfirmation.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>Reset your inventory?</code> | PendingConfirmation — generated/display copy |
| 17 | <code>This deletes every room scan and item you've submitted. You'll need to scan your home again from scratch. This can't be undone.</code> | PendingConfirmation — generated/display copy |

### `Peezy 4.0/Tasks/Views/ResetInventoryOverlay.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 8 | <code>Resetting inventory...</code> | ResetInventoryOverlay — generated/display copy |

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

### `Peezy 4.0/Tasks/Views/TasksList.swift`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 28 | <code>You're on track. New tasks drop in daily.</code> | TasksList — generated/display copy |
| 43 | <code>Nothing in the works yet.</code> | TasksList — generated/display copy |
| 61 | <code>Completed tasks will stack up here.</code> | TasksList — generated/display copy |

## Data-driven and callable strings

### `functions/flowDefinitionsData.json`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 15 | <code>Block the day after move day — unpacking always runs longer than expected. Without time off, you'll be answering Slack with a couch on your back.</code> | FlowEngine schedule_time_off_work — body |
| 37 | <code>Confirm payroll updated 'work state for taxes' — addresses don't sync. Wrong state withholding turns next April into a W-2 nightmare.</code> | FlowEngine update_employer_records — body |
| 59 | <code>Buy 20% more small boxes than you think — books, kitchen stuff, and bathroom items fill them fast. Big boxes get dangerously heavy.</code> | FlowEngine buy_packing_supplies — body |
| 81 | <code>A freezer that's not fully defrosted leaks across the moving truck floor and ruins cardboard boxes on contact.</code> | FlowEngine defrost_freezer — body |
| 104 | <code>Pack a 'last bag' with cleaning supplies — load it onto the truck last. Once boxes are sealed, finding a sponge becomes a 30-minute hunt.</code> | FlowEngine diy_deep_cleaning — body |
| 110 | <code>Clean inside the oven and fridge first — they're the top deduction trigger. One missed area can cost you hundreds in deposit deductions.</code> | FlowEngine diy_deep_cleaning — body |
| 132 | <code>Bring a flashlight — corners and closets hide more than you think. A forgotten item or dusty corner is exactly what landlords cite.</code> | FlowEngine diy_final_cleaning — body |
| 154 | <code>Set up USPS mail forwarding online ($1.10 fee). Takes effect in 7-10 business days — do this 2 weeks before move day. Forwarding applies to the whole household, not individuals.</code> | FlowEngine forward_mail_usps — body |
| 176 | <code>Contact the registrar with your new address and proof of residency. Also update emergency contacts, bus routes, and after-school programs.</code> | FlowEngine coa_schools — body |
| 198 | <code>Give your current daycare 2-4 weeks written notice. Request copies of developmental records and immunization history. Ask for recommendations near your new address.</code> | FlowEngine transfer_daycare — body |
| 220 | <code>Start calling providers now — waitlists for infant and toddler spots can be 3-6 months. Contact at least 5 providers near your new address, ask about openings for your child's age group, and get on every waitlist. It costs nothing and saves you from scrambling after the move.</code> | FlowEngine setup_daycare — body |
| 259 | <code>Is this your new address?</code> | FlowEngine setup_utilities — question |
| 267 | <code>We'll contact the utility providers to set up service at your new address before you arrive.</code> | FlowEngine setup_utilities — body |
| 268 | <code>Response times are typically 24–48 hours.</code> | FlowEngine setup_utilities — subtext |
| 273 | <code>Get a 'letter of credit' from your old utility — waives the deposit.</code> | FlowEngine setup_utilities — body |
| 312 | <code>Is this your current address?</code> | FlowEngine cancel_utilities — question |
| 320 | <code>We'll contact each provider to schedule shutoffs at your current address after you move out.</code> | FlowEngine cancel_utilities — body |
| 321 | <code>Response times are typically 24–48 hours.</code> | FlowEngine cancel_utilities — subtext |
| 326 | <code>Give them your forwarding address — credit refunds arrive by mail.</code> | FlowEngine cancel_utilities — body |
| 365 | <code>Is this your new address?</code> | FlowEngine transfer_utilities — question |
| 373 | <code>We'll contact each provider to transfer service to your new address with no overlap in billing.</code> | FlowEngine transfer_utilities — body |
| 374 | <code>Response times are typically 24–48 hours.</code> | FlowEngine transfer_utilities — subtext |
| 379 | <code>Same provider = no new deposit, no credit check, no setup fee.</code> | FlowEngine transfer_utilities — body |
| 401 | <code>What would you like to do?</code> | FlowEngine manage_vet — question |
| 445 | <code>Who's your vet?</code> | FlowEngine manage_vet — question |
| 453 | <code>We'll reach out to your vet and get your address updated.</code> | FlowEngine manage_vet — body |
| 454 | <code>Response times are typically 24–48 hours.</code> | FlowEngine manage_vet — subtext |
| 459 | <code>Most vet offices let you update your address by calling the front desk or through their patient portal.</code> | FlowEngine manage_vet — body |
| 469 | <code>Want help transferring your records?</code> | FlowEngine manage_vet — question |
| 485 | <code>Who's your current vet?</code> | FlowEngine manage_vet — question |
| 493 | <code>Would you like help finding a new vet near your new place?</code> | FlowEngine manage_vet — question |
| 516 | <code>We'll help find you a new vet near your new place.</code> | FlowEngine manage_vet — body |
| 517 | <code>Response times are typically 24–48 hours.</code> | FlowEngine manage_vet — subtext |
| 524 | <code>We'll transfer your records and help find you a new vet.</code> | FlowEngine manage_vet — body |
| 530 | <code>We'll transfer your records. You're all set to find a new one on your own.</code> | FlowEngine manage_vet — body |
| 537 | <code>Call the front desk to request a records transfer — make sure vaccination records are included. For the new place, ask other pet owners in your new neighborhood for recommendations.</code> | FlowEngine manage_vet — body |
| 559 | <code>What would you like to do?</code> | FlowEngine transfer_pharmacy_records — question |
| 603 | <code>Which pharmacy do you use?</code> | FlowEngine transfer_pharmacy_records — question |
| 611 | <code>We'll reach out to your pharmacy and get your address updated.</code> | FlowEngine transfer_pharmacy_records — body |
| 612 | <code>Response times are typically 24–48 hours.</code> | FlowEngine transfer_pharmacy_records — subtext |
| 617 | <code>Most pharmacies let you update your address online or through their app. Have your prescription numbers handy.</code> | FlowEngine transfer_pharmacy_records — body |
| 627 | <code>Want help transferring your prescriptions?</code> | FlowEngine transfer_pharmacy_records — question |
| 643 | <code>Which pharmacy do you use?</code> | FlowEngine transfer_pharmacy_records — question |
| 651 | <code>Would you like help finding a new pharmacy near your new place?</code> | FlowEngine transfer_pharmacy_records — question |
| 674 | <code>We'll help find you a new pharmacy near your new place.</code> | FlowEngine transfer_pharmacy_records — body |
| 675 | <code>Response times are typically 24–48 hours.</code> | FlowEngine transfer_pharmacy_records — subtext |
| 682 | <code>We'll transfer your prescriptions and help find you a new pharmacy.</code> | FlowEngine transfer_pharmacy_records — body |
| 688 | <code>We'll transfer your prescriptions. You're all set to find a new one on your own.</code> | FlowEngine transfer_pharmacy_records — body |
| 695 | <code>Most pharmacies can transfer prescriptions with just a phone call to the new location. Give them your name, date of birth, and current pharmacy — they handle the rest.</code> | FlowEngine transfer_pharmacy_records — body |
| 717 | <code>Check your state — many let you update online without an appointment. An outdated address can void traffic ticket service and jury duty notices.</code> | FlowEngine handle_dmv_local — body |
| 740 | <code>Request REAL ID — TSA needs a new one in your new state. Driving past the deadline on an out-of-state license is a moving violation.</code> | FlowEngine handle_dmv_interstate — body |
| 748 | <code>Update auto insurance first — DMV won't register without it. Outdated tags risk tickets, towing, and insurance denial in a crash.</code> | FlowEngine handle_dmv_interstate — body |
| 787 | <code>Is this where you're loading from?</code> | FlowEngine reserve_access_old — question |
| 795 | <code>Is this your move date?</code> | FlowEngine reserve_access_old — question |
| 801 | <code>We'll contact your current building and reserve {rowsList} for move day.</code> | FlowEngine reserve_access_old — body |
| 806 | <code>Response times are typically 24–48 hours.</code> | FlowEngine reserve_access_old — subtext |
| 811 | <code>Reserve two adjacent spots — trucks need ramp clearance too.</code> | FlowEngine reserve_access_old — body |
| 850 | <code>Is this where you're unloading?</code> | FlowEngine reserve_access_new — question |
| 858 | <code>Is this your move date?</code> | FlowEngine reserve_access_new — question |
| 864 | <code>We'll contact your new building and reserve {rowsList} for move day.</code> | FlowEngine reserve_access_new — body |
| 869 | <code>Response times are typically 24–48 hours.</code> | FlowEngine reserve_access_new — subtext |
| 874 | <code>Ask the building to cone off the spot the night before.</code> | FlowEngine reserve_access_new — body |
| 897 | <code>Shoot video too — it captures context photos miss. Slumlords count on you not having proof.</code> | FlowEngine protect_deposit — body |
| 904 | <code>A missing $5 fob can cost $200 in lock-change charges. Photograph everything you're returning the moment you hand it over.</code> | FlowEngine protect_deposit — body |
| 927 | <code>Give the school at least 2-4 weeks written notice. Request sealed transcripts and a records transfer packet — the new school will need immunization records, IEP documents if applicable, and proof of completed coursework.</code> | FlowEngine school_transfer — body |
| 934 | <code>Contact the new district's enrollment office before you move. You'll need proof of residency at the new address, immunization records, and your child's birth certificate. Many districts let you start the paperwork online.</code> | FlowEngine school_transfer — body |
| 976 | <code>Who's your primary care doctor?</code> | FlowEngine medical_records — question |
| 981 | <code>Who's your dentist?</code> | FlowEngine medical_records — question |
| 986 | <code>Who's your specialist?</code> | FlowEngine medical_records — question |
| 996 | <code>We'll reach out to each office and get your records moving.</code> | FlowEngine medical_records — body |
| 997 | <code>Response times are typically 24–48 hours.</code> | FlowEngine medical_records — subtext |
| 1002 | <code>Call the front desk to request a records transfer — most offices can send them electronically.</code> | FlowEngine medical_records — body |
| 1044 | <code>Which bank are you with?</code> | FlowEngine financial_accounts — question |
| 1049 | <code>Which credit card company?</code> | FlowEngine financial_accounts — question |
| 1054 | <code>Which brokerage are you with?</code> | FlowEngine financial_accounts — question |
| 1059 | <code>Who services your student loans?</code> | FlowEngine financial_accounts — question |
| 1069 | <code>We'll reach out to each of them and get your address updated.</code> | FlowEngine financial_accounts — body |
| 1070 | <code>Response times are typically 24–48 hours.</code> | FlowEngine financial_accounts — subtext |
| 1075 | <code>Update billing addresses before your next statement closes — mismatches trigger fraud alerts and declined transactions.</code> | FlowEngine financial_accounts — body |
| 1117 | <code>Which gym do you go to?</code> | FlowEngine memberships — question |
| 1122 | <code>Which studio do you go to?</code> | FlowEngine memberships — question |
| 1127 | <code>Which studio do you go to?</code> | FlowEngine memberships — question |
| 1132 | <code>Which spa do you go to?</code> | FlowEngine memberships — question |
| 1137 | <code>Which club are you a member of?</code> | FlowEngine memberships — question |
| 1147 | <code>We'll contact each of them — cancellations, transfers, and address updates handled.</code> | FlowEngine memberships — body |
| 1148 | <code>Response times are typically 24–48 hours.</code> | FlowEngine memberships — subtext |
| 1153 | <code>Check your membership terms for cancellation requirements — some need 30 days written notice.</code> | FlowEngine memberships — body |
| 1175 | <code>Want us to find you the right unit?</code> | FlowEngine storage_unit — question |
| 1193 | <code>We'll scout units near your new place and come back with the best options.</code> | FlowEngine storage_unit — body |
| 1194 | <code>Response times are typically 24–48 hours.</code> | FlowEngine storage_unit — subtext |
| 1199 | <code>Book two weeks out — first-month-free deals go to early reservations.</code> | FlowEngine storage_unit — body |

### `functions/index.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 33 | <code>Hey! Thanks for reaching out. We'll get back to you within a few hours during business hours (9am-6pm CT). For urgent issues, reply 'URGENT' and we'll prioritize.</code> | Support chat — first-message auto-acknowledgment |
| 118 | <code>I'm having trouble loading my knowledge base. Try again in a moment.</code> | HTTP text payload |
| 132 | <code>You're moving fast! Give me a moment to catch up. Try again in a few seconds.</code> | HTTP text payload |
| 194 | <code>Something went sideways on my end. Mind trying that again?</code> | HTTP text payload |
| 590 | <code>Must be signed in to delete account.</code> | callable error |
| 636 | <code>Account deletion failed. Please try again or contact support.</code> | callable error |

### `functions/ispPlansData.json`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 13 | <code>A straightforward symmetrical fiber option for busy connected homes.</code> | ISP plan catalog google_fiber_core_1_gig — why |
| 28 | <code>A lower-cost fiber tier with enough speed for streaming and video calls.</code> | ISP plan catalog att_fiber_300 — why |
| 43 | <code>A price-guaranteed cable option for everyday work, play, and streaming.</code> | ISP plan catalog xfinity_300 — why |
| 58 | <code>A mid-tier cable option for households with several active devices.</code> | ISP plan catalog spectrum_internet_premier — why |
| 73 | <code>A quick self-install wireless option where wired service is inconvenient.</code> | ISP plan catalog tmobile_rely_home_internet — why |

### `functions/joinWaitlist.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 133 | <code>Too many requests. Try again in a minute.</code> | HTTP error payload |
| 141 | <code>Please enter a valid email address.</code> | HTTP error payload |
| 216 | <code>Something went wrong on our end. Please try again.</code> | HTTP error payload |

### `functions/miniAssessmentWorkflows.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 26 | <code>Let's make sure all your financial accounts get your new address.</code> | Mini assessment address_change_financial — subtitle |
| 27 | <code>Swipe right if you have an account, left if you don't. We'll ask for names after.</code> | Mini assessment address_change_financial — instruction |
| 33 | <code>Do you have a bank or credit union account?</code> | Mini assessment address_change_financial — question |
| 35 | <code>Which bank/credit union?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 41 | <code>Do you have any credit cards?</code> | Mini assessment address_change_financial — question |
| 43 | <code>Which credit cards?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 49 | <code>Do you have investment or brokerage accounts?</code> | Mini assessment address_change_financial — question |
| 51 | <code>Which brokerages?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 57 | <code>Do you have a 401k or IRA?</code> | Mini assessment address_change_financial — question |
| 59 | <code>Which provider?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 64 | <code>Do you have any loans (auto, student, personal)?</code> | Mini assessment address_change_financial — question |
| 66 | <code>Which lenders?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 72 | <code>Do you have a mortgage?</code> | Mini assessment address_change_financial — question |
| 74 | <code>Which lender?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 79 | <code>Do you have an HSA or FSA account?</code> | Mini assessment address_change_financial — question |
| 81 | <code>Which provider?</code> | Mini assessment address_change_financial — textEntryPrompt |
| 88 | <code>Here's what we found:</code> | Mini assessment address_change_financial — subtitle |
| 113 | <code>Let's update your healthcare providers with your new address.</code> | Mini assessment address_change_health — subtitle |
| 114 | <code>Swipe right if you have this, left if you don't.</code> | Mini assessment address_change_health — instruction |
| 120 | <code>Do you have a primary care doctor?</code> | Mini assessment address_change_health — question |
| 122 | <code>Doctor's name or practice?</code> | Mini assessment address_change_health — textEntryPrompt |
| 127 | <code>Do you have a dentist?</code> | Mini assessment address_change_health — question |
| 129 | <code>Dentist's name or practice?</code> | Mini assessment address_change_health — textEntryPrompt |
| 134 | <code>Do you have health insurance?</code> | Mini assessment address_change_health — question |
| 136 | <code>Which provider?</code> | Mini assessment address_change_health — textEntryPrompt |
| 141 | <code>Do you have dental insurance?</code> | Mini assessment address_change_health — question |
| 143 | <code>Which provider?</code> | Mini assessment address_change_health — textEntryPrompt |
| 148 | <code>Do you have vision insurance or an eye doctor?</code> | Mini assessment address_change_health — question |
| 150 | <code>Provider or doctor?</code> | Mini assessment address_change_health — textEntryPrompt |
| 155 | <code>Do you see a therapist or counselor?</code> | Mini assessment address_change_health — question |
| 157 | <code>Therapist's name?</code> | Mini assessment address_change_health — textEntryPrompt |
| 162 | <code>Do you see any specialists?</code> | Mini assessment address_change_health — question |
| 164 | <code>Which specialists?</code> | Mini assessment address_change_health — textEntryPrompt |
| 170 | <code>Do you have a regular pharmacy?</code> | Mini assessment address_change_health — question |
| 172 | <code>Which pharmacy?</code> | Mini assessment address_change_health — textEntryPrompt |
| 179 | <code>Here's what we found:</code> | Mini assessment address_change_health — subtitle |
| 204 | <code>Insurance companies need your new address - rates can change by location!</code> | Mini assessment address_change_insurance — subtitle |
| 205 | <code>Swipe right if you have this coverage, left if you don't.</code> | Mini assessment address_change_insurance — instruction |
| 211 | <code>Do you have auto insurance?</code> | Mini assessment address_change_insurance — question |
| 213 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 218 | <code>Do you have renters insurance?</code> | Mini assessment address_change_insurance — question |
| 220 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 225 | <code>Do you have homeowners insurance?</code> | Mini assessment address_change_insurance — question |
| 227 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 232 | <code>Do you have life insurance?</code> | Mini assessment address_change_insurance — question |
| 234 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 239 | <code>Do you have umbrella insurance?</code> | Mini assessment address_change_insurance — question |
| 241 | <code>Which company?</code> | Mini assessment address_change_insurance — textEntryPrompt |
| 248 | <code>Here's what we found:</code> | Mini assessment address_change_insurance — subtitle |
| 273 | <code>Let's identify memberships that need to be transferred or canceled.</code> | Mini assessment address_change_fitness — subtitle |
| 274 | <code>Swipe right if you have this membership, left if you don't.</code> | Mini assessment address_change_fitness — instruction |
| 280 | <code>Do you have a gym membership?</code> | Mini assessment address_change_fitness — question |
| 282 | <code>Which gym?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 287 | <code>Are you a CrossFit member?</code> | Mini assessment address_change_fitness — question |
| 289 | <code>Which box?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 294 | <code>Do you have a yoga studio membership?</code> | Mini assessment address_change_fitness — question |
| 296 | <code>Which studio?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 301 | <code>Do you have a Pilates membership?</code> | Mini assessment address_change_fitness — question |
| 303 | <code>Which studio?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 308 | <code>Do you do spin or cycling classes?</code> | Mini assessment address_change_fitness — question |
| 310 | <code>Which studio?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 315 | <code>Do you have a pool or swim club membership?</code> | Mini assessment address_change_fitness — question |
| 317 | <code>Which pool/club?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 322 | <code>Are you a country club member?</code> | Mini assessment address_change_fitness — question |
| 324 | <code>Which club?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 329 | <code>Do you have a spa or massage membership?</code> | Mini assessment address_change_fitness — question |
| 331 | <code>Which spa?</code> | Mini assessment address_change_fitness — textEntryPrompt |
| 338 | <code>Here's what we found:</code> | Mini assessment address_change_fitness — subtitle |
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
| 414 | <code>Any other memberships?</code> | Mini assessment address_change_memberships — question |
| 416 | <code>What memberships?</code> | Mini assessment address_change_memberships — textEntryPrompt |
| 424 | <code>Here's what we found:</code> | Mini assessment address_change_memberships — subtitle |
| 449 | <code>Let's make sure nothing gets delivered to your old address!</code> | Mini assessment address_change_subscriptions — subtitle |
| 450 | <code>Swipe right if you subscribe to this, left if you don't.</code> | Mini assessment address_change_subscriptions — instruction |
| 456 | <code>Do you get meal kits delivered?</code> | Mini assessment address_change_subscriptions — question |
| 458 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 463 | <code>Do you get pet food or supplies delivered?</code> | Mini assessment address_change_subscriptions — question |
| 465 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 470 | <code>Do you subscribe to vitamins or supplements?</code> | Mini assessment address_change_subscriptions — question |
| 472 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 477 | <code>Do you get coffee delivered?</code> | Mini assessment address_change_subscriptions — question |
| 479 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 484 | <code>Are you in a wine club?</code> | Mini assessment address_change_subscriptions — question |
| 486 | <code>Which club?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 491 | <code>Do you get beauty products delivered?</code> | Mini assessment address_change_subscriptions — question |
| 493 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 498 | <code>Do you have a clothing subscription?</code> | Mini assessment address_change_subscriptions — question |
| 500 | <code>Which service?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 505 | <code>Any other subscription deliveries?</code> | Mini assessment address_change_subscriptions — question |
| 507 | <code>What subscriptions?</code> | Mini assessment address_change_subscriptions — textEntryPrompt |
| 515 | <code>Here's what we found:</code> | Mini assessment address_change_subscriptions — subtitle |

### `functions/peezyBrain.js`

| Line | Current text | Screen / context |
| ---: | --- | --- |
| 50 | <code>What's on your mind about the move?</code> | HTTP text payload |
| 129 | <code>I'm getting a lot of requests right now. Give me a sec and try again?</code> | HTTP text payload |
| 139 | <code>Give me just a second - I want to make sure I get this right. Mind trying that again?</code> | HTTP text payload |
| 149 | <code>Something's not working on my end right now. Can you try again in a minute?</code> | HTTP text payload |
| 160 | <code>Having a technical issue on my end. The team's been notified.</code> | HTTP text payload |
| 169 | <code>Something went sideways. Try sending that again?</code> | HTTP text payload |

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
| 15 | <code>Get binding estimates from three USDOT-licensed movers. Book 8-12 weeks out for summer moves, 4-6 weeks off-season.</code> | Task catalog BOOK_MOVERS — desc |
| 18 | <code>Get a binding estimate — federal law caps your final bill at 110%.</code> | Task catalog BOOK_MOVERS — tips |
| 20 | <code>Booking late means leftover dates, leftover crews, and leftover quality.</code> | Task catalog BOOK_MOVERS — whyNeeded |
| 35 | <code>Schedule a move-out deep clean for the day after your movers finish. Get three quotes and confirm scope in writing.</code> | Task catalog BOOK_CLEANERS — desc |
| 38 | <code>Insist 'inside appliances' is in writing — most charge extra otherwise.</code> | Task catalog BOOK_CLEANERS — tips |
| 40 | <code>One missed area can cost you your entire security deposit.</code> | Task catalog BOOK_CLEANERS — whyNeeded |
| 55 | <code>Compare U-Haul, Penske, and Budget on size, mileage, and total cost. Reserve 4-6 weeks out — earlier in summer.</code> | Task catalog RENT_TRUCK — desc |
| 58 | <code>Size up if borderline — one trip always beats two.</code> | Task catalog RENT_TRUCK — tips |
| 60 | <code>Late means the wrong size, wrong pickup location, or no truck at all.</code> | Task catalog RENT_TRUCK — whyNeeded |
| 71 | <code>Order service 2-3 weeks ahead. Ask for self-install if your home is pre-wired — it saves $50-100 and a technician window.</code> | Task catalog SETUP_INTERNET — desc |
| 74 | <code>Self-install saves $50-100 — confirm your address qualifies first.</code> | Task catalog SETUP_INTERNET — tips |
| 76 | <code>Without it, you're tethering work calls to your phone for days.</code> | Task catalog SETUP_INTERNET — whyNeeded |
| 94 | <code>List on Facebook Marketplace, OfferUp, or Craigslist 4+ weeks out. Drop the price 10-20% every three days until it sells.</code> | Task catalog SELL_ITEMS — desc |
| 97 | <code>Post photos in natural daylight — listings sell twice as fast.</code> | Task catalog SELL_ITEMS — tips |
| 99 | <code>Every unsold item becomes a box you pay to move.</code> | Task catalog SELL_ITEMS — whyNeeded |
| 117 | <code>Book a free pickup with Salvation Army or Habitat ReStore 3-4 weeks out — peak season wait times stretch to a month.</code> | Task catalog REMOVE_ITEMS — desc |
| 120 | <code>Get an itemized receipt at pickup — it's a tax write-off.</code> | Task catalog REMOVE_ITEMS — tips |
| 122 | <code>Last-minute, you'll be hauling furniture to the curb yourself.</code> | Task catalog REMOVE_ITEMS — whyNeeded |
| 137 | <code>Update your address if staying. If switching, request vaccination records, lab results, and any chronic-care notes for your new vet.</code> | Task catalog MANAGE_VET — desc |
| 140 | <code>Get the rabies certificate separately — boarding facilities require it on-site.</code> | Task catalog MANAGE_VET — tips |
| 142 | <code>Without records, boarding kennels and ER vets may turn you away.</code> | Task catalog MANAGE_VET — whyNeeded |
| 152 | <code>File a USPS change of address ($1.10 verification fee). First-class mail forwards free for 12 months from your start date.</code> | Task catalog FORWARD_MAIL_USPS — desc |
| 155 | <code>Marketing mail and magazines don't forward — update senders directly.</code> | Task catalog FORWARD_MAIL_USPS — tips |
| 157 | <code>Anything sent to your old address — bills, tax docs, checks — vanishes.</code> | Task catalog FORWARD_MAIL_USPS — whyNeeded |
| 169 | <code>Request 2-3 days minimum: one for packing, moving day, and one to recover. Submit at least four weeks ahead.</code> | Task catalog SCHEDULE_TIME_OFF_WORK — desc |
| 172 | <code>Block the day after move day — unpacking always runs longer than expected.</code> | Task catalog SCHEDULE_TIME_OFF_WORK — tips |
| 174 | <code>Without time off, you'll be answering Slack with a couch on your back.</code> | Task catalog SCHEDULE_TIME_OFF_WORK — whyNeeded |
| 185 | <code>Update your home address with HR. If you crossed state lines, also update your work-state W-4 — addresses and taxes are tracked separately.</code> | Task catalog UPDATE_EMPLOYER_RECORDS — desc |
| 188 | <code>Confirm payroll updated 'work state for taxes' — addresses don't sync.</code> | Task catalog UPDATE_EMPLOYER_RECORDS — tips |
| 190 | <code>Wrong state withholding turns next April into a W-2 nightmare.</code> | Task catalog UPDATE_EMPLOYER_RECORDS — whyNeeded |
| 204 | <code>Schedule shutoffs for electric, gas, water, sewer, and trash. Set the date for the day after you move out, not the day of.</code> | Task catalog CANCEL_UTILITIES — desc |
| 207 | <code>Give them your forwarding address — credit refunds arrive by mail.</code> | Task catalog CANCEL_UTILITIES — tips |
| 209 | <code>Utilities running in your name after move-out keep billing you.</code> | Task catalog CANCEL_UTILITIES — whyNeeded |
| 224 | <code>Call electric, gas, water, and trash providers 2-3 weeks ahead. Schedule activation the day before you arrive — overlap beats outage.</code> | Task catalog SETUP_UTILITIES — desc |
| 227 | <code>Get a 'letter of credit' from your old utility — waives the deposit.</code> | Task catalog SETUP_UTILITIES — tips |
| 229 | <code>Arriving at a dark, waterless house ruins your first night.</code> | Task catalog SETUP_UTILITIES — whyNeeded |
| 244 | <code>Call each provider 1-2 weeks out. Schedule the new address active a day before, the old address shutoff a day after.</code> | Task catalog TRANSFER_UTILITIES — desc |
| 247 | <code>Same provider = no new deposit, no credit check, no setup fee.</code> | Task catalog TRANSFER_UTILITIES — tips |
| 249 | <code>Without overlap, you'll lose water mid-clean or power mid-move.</code> | Task catalog TRANSFER_UTILITIES — whyNeeded |
| 267 | <code>Submit your new address with proof of residency. Update emergency contacts, transportation requests, and pickup authorizations the same day.</code> | Task catalog COA_SCHOOLS — desc |
| 270 | <code>Bus zones change at the address level — confirm yours immediately.</code> | Task catalog COA_SCHOOLS — tips |
| 272 | <code>An old address can drop your kid from the bus route overnight.</code> | Task catalog COA_SCHOOLS — whyNeeded |
| 290 | <code>Get on multiple waitlists immediately — infant care can take 12-24 months. Tour in person and ask about ratios, licensing, and turnover.</code> | Task catalog SETUP_DAYCARE — desc |
| 293 | <code>Send a handwritten thank-you after touring — directors remember you.</code> | Task catalog SETUP_DAYCARE — tips |
| 295 | <code>Waitlists can outlast your move date by a full year.</code> | Task catalog SETUP_DAYCARE — whyNeeded |
| 313 | <code>Email the director with your new address, updated emergency contacts, and any drop-off or pickup time changes.</code> | Task catalog TRANSFER_DAYCARE — desc |
| 316 | <code>Update authorized pickup list in writing — verbal changes don't stick.</code> | Task catalog TRANSFER_DAYCARE — tips |
| 318 | <code>Outdated emergency contacts can block pickup if your child gets hurt.</code> | Task catalog TRANSFER_DAYCARE — whyNeeded |
| 336 | <code>Call the new pharmacy with your old pharmacy's name and number — they handle the transfer in minutes for chain stores.</code> | Task catalog TRANSFER_PHARMACY_RECORDS — desc |
| 339 | <code>Controlled prescriptions don't transfer — get a new one from your doctor.</code> | Task catalog TRANSFER_PHARMACY_RECORDS — tips |
| 341 | <code>Running out mid-move means an urgent care visit just to refill.</code> | Task catalog TRANSFER_PHARMACY_RECORDS — whyNeeded |
| 356 | <code>Notify your insurer with the new address before move day. Premiums shift by ZIP code — sometimes by hundreds per year.</code> | Task catalog UPDATE_AUTO_INSURANCE — desc |
| 359 | <code>Get three new quotes the same day — ZIP changes are perfect leverage.</code> | Task catalog UPDATE_AUTO_INSURANCE — tips |
| 361 | <code>Wrong address on file can void your coverage in a claim.</code> | Task catalog UPDATE_AUTO_INSURANCE — whyNeeded |
| 380 | <code>Call your insurer with your move-out date. Schedule cancellation for the day after closing or possession transfer to avoid coverage gaps.</code> | Task catalog CANCEL_CONDO_INSURANCE — desc |
| 383 | <code>Ask for a prorated refund — most insurers owe you for unused months.</code> | Task catalog CANCEL_CONDO_INSURANCE — tips |
| 385 | <code>Cancel too early and a last-day flood becomes your problem alone.</code> | Task catalog CANCEL_CONDO_INSURANCE — whyNeeded |
| 403 | <code>Call your insurer to cancel — most do it online in 5 minutes. Schedule the end date for the day you hand back keys.</code> | Task catalog CANCEL_RENTERS_INSURANCE — desc |
| 406 | <code>Ask for the unused premium back — you're owed a prorated refund.</code> | Task catalog CANCEL_RENTERS_INSURANCE — tips |
| 408 | <code>Canceling before key return leaves your stuff uninsured during the last load.</code> | Task catalog CANCEL_RENTERS_INSURANCE — whyNeeded |
| 427 | <code>Get an HO6 policy effective on closing day. Read the HOA master policy first — it determines whether you need walls-in or full coverage.</code> | Task catalog SETUP_CONDO_INSURANCE — desc |
| 430 | <code>Ask the HOA which master policy type — bare walls, walls-in, or all-in.</code> | Task catalog SETUP_CONDO_INSURANCE — tips |
| 432 | <code>The wrong HO6 leaves your floors and cabinets unprotected after a leak.</code> | Task catalog SETUP_CONDO_INSURANCE — whyNeeded |
| 450 | <code>Lock in coverage 2-3 weeks before closing. Lenders require a paid first year and proof of binder before they'll fund the loan.</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — desc |
| 453 | <code>Quote at least three insurers — premiums vary 30%+ for identical coverage.</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — tips |
| 455 | <code>Without an active binder at closing, the deal stalls and your move with it.</code> | Task catalog SETUP_HOMEOWNERS_INSURANCE — whyNeeded |
| 473 | <code>Quote online with Lemonade, State Farm, or your auto insurer. Most policies run $15-30/month and bind in under ten minutes.</code> | Task catalog SETUP_RENTERS_INSURANCE — desc |
| 476 | <code>Bundle with auto insurance — usually saves 5-15% on both.</code> | Task catalog SETUP_RENTERS_INSURANCE — tips |
| 478 | <code>One pipe burst can wipe out your belongings without coverage.</code> | Task catalog SETUP_RENTERS_INSURANCE — whyNeeded |
| 496 | <code>Call your insurer 2-3 weeks ahead with the new address. Verify the new HOA master policy type — coverage needs may shift.</code> | Task catalog TRANSFER_CONDO_INSURANCE — desc |
| 499 | <code>Different HOAs = different coverage needs — re-quote, don't just transfer.</code> | Task catalog TRANSFER_CONDO_INSURANCE — tips |
| 501 | <code>An assumed transfer can leave gaps your old policy covered automatically.</code> | Task catalog TRANSFER_CONDO_INSURANCE — whyNeeded |
| 525 | <code>Call your insurer 3-4 weeks before closing. Premiums shift with location, age, square footage, and roof — get a new quote either way.</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — desc |
| 528 | <code>Re-quote three insurers — transfers rarely beat fresh-quote pricing.</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — tips |
| 530 | <code>A 'transfer' often hides a premium increase you'd catch by shopping.</code> | Task catalog TRANSFER_HOMEOWNERS_INSURANCE — whyNeeded |
| 548 | <code>Call your insurer with the new address 1-2 weeks ahead. Transferring keeps your claims-free discount and skips the new policy fee.</code> | Task catalog TRANSFER_RENTERS_INSURANCE — desc |
| 551 | <code>Ask for the multi-year loyalty discount — most insurers don't volunteer it.</code> | Task catalog TRANSFER_RENTERS_INSURANCE — tips |
| 553 | <code>Restarting fresh resets discounts you've spent years earning.</code> | Task catalog TRANSFER_RENTERS_INSURANCE — whyNeeded |
| 566 | <code>Pan your camera slowly across each room. Peezy's AI identifies furniture, appliances, and large items in about 20 seconds per room.</code> | Task catalog SCAN_INVENTORY — desc |
| 569 | <code>Open closets and cabinets — Peezy catches what you'd forget to mention.</code> | Task catalog SCAN_INVENTORY — tips |
| 571 | <code>An accurate inventory unlocks precise quotes and protects you against damage claims.</code> | Task catalog SCAN_INVENTORY — whyNeeded |
| 582 | <code>Empty the contents, unplug it, prop the doors open, and lay towels underneath. Plan 24-48 hours before move day.</code> | Task catalog DEFROST_FREEZER — desc |
| 585 | <code>After moving, let it sit upright for 4 hours before plugging back in.</code> | Task catalog DEFROST_FREEZER — tips |
| 587 | <code>Movers won't load a wet or leaking fridge — full stop.</code> | Task catalog DEFROST_FREEZER — whyNeeded |
| 602 | <code>Plan 6+ hours with two people. Hit appliances, baseboards, walls, windows, vents, and cabinets — landlords inspect every one.</code> | Task catalog DIY_DEEP_CLEANING — desc |
| 605 | <code>Clean inside the oven and fridge first — they're the top deduction trigger.</code> | Task catalog DIY_DEEP_CLEANING — tips |
| 607 | <code>One missed area can cost you hundreds in deposit deductions.</code> | Task catalog DIY_DEEP_CLEANING — whyNeeded |
| 622 | <code>After everything is out, walk every room, closet, and cabinet. Wipe baseboards, sweep floors, and confirm nothing is left behind.</code> | Task catalog DIY_FINAL_CLEANING — desc |
| 625 | <code>Bring a flashlight — corners and closets hide more than you think.</code> | Task catalog DIY_FINAL_CLEANING — tips |
| 627 | <code>A forgotten item or dusty corner is exactly what landlords cite.</code> | Task catalog DIY_FINAL_CLEANING — whyNeeded |
| 648 | <code>Call your insurer once the sale closes. Set the cancellation date for the day after closing — never before.</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — desc |
| 651 | <code>Ask for the prepaid premium refund — most owe you for unused months.</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — tips |
| 653 | <code>Canceling early voids coverage during the final walkthrough and key transfer.</code> | Task catalog CANCEL_HOMEOWNERS_INSURANCE — whyNeeded |
| 669 | <code>Bring your current license and two proofs of new address to the DMV. Most states require updates within 30 days.</code> | Task catalog HANDLE_DMV_LOCAL — desc |
| 672 | <code>Check your state — many let you update online without an appointment.</code> | Task catalog HANDLE_DMV_LOCAL — tips |
| 674 | <code>An outdated address can void traffic ticket service and jury duty notices.</code> | Task catalog HANDLE_DMV_LOCAL — whyNeeded |
| 689 | <code>One DMV trip covers it: new license, and vehicle registration if you drive. Most states give you 30 days after the move.</code> | Task catalog HANDLE_DMV_INTERSTATE — desc |
| 692 | <code>Request REAL ID — TSA needs a new one in your new state.</code> | Task catalog HANDLE_DMV_INTERSTATE — tips |
| 694 | <code>Driving past the deadline on an out-of-state license is a moving violation.</code> | Task catalog HANDLE_DMV_INTERSTATE — whyNeeded |
| 715 | <code>Lock in truck parking — and the service elevator if your building has one — before move day.</code> | Task catalog RESERVE_ACCESS_OLD — desc |
| 718 | <code>Reserve two adjacent spots — trucks need ramp clearance too.</code> | Task catalog RESERVE_ACCESS_OLD — tips |
| 720 | <code>No reserved access means movers burn paid hours hunting for parking.</code> | Task catalog RESERVE_ACCESS_OLD — whyNeeded |
| 750 | <code>Lock in truck parking at the new building — and the service elevator if there is one — before the truck arrives.</code> | Task catalog RESERVE_ACCESS_NEW — desc |
| 753 | <code>Ask the building to cone off the spot the night before.</code> | Task catalog RESERVE_ACCESS_NEW — tips |
| 755 | <code>An unreserved elevator is the #1 cause of movers' overtime charges.</code> | Task catalog RESERVE_ACCESS_NEW — whyNeeded |
| 784 | <code>Photograph the empty unit, return every key and fob, and keep the record — your deposit's evidence file.</code> | Task catalog PROTECT_DEPOSIT — desc |
| 787 | <code>Shoot video too — it captures context photos miss.</code> | Task catalog PROTECT_DEPOSIT — tips |
| 789 | <code>Without proof, deductions are your word against theirs.</code> | Task catalog PROTECT_DEPOSIT — whyNeeded |
| 807 | <code>Notify the current school, request records, and start enrollment at the new district — one parental job, one card.</code> | Task catalog SCHOOL_TRANSFER — desc |
| 810 | <code>Many districts let you start enrollment paperwork online before you arrive.</code> | Task catalog SCHOOL_TRANSFER — tips |
| 812 | <code>Enrollment gaps cost kids school days.</code> | Task catalog SCHOOL_TRANSFER — whyNeeded |
| 829 | <code>One pass across your providers — records requested, addresses updated, transfers started.</code> | Task catalog MEDICAL_RECORDS — desc |
| 832 | <code>Call the front desk — most offices send records electronically in days.</code> | Task catalog MEDICAL_RECORDS — tips |
| 834 | <code>New providers can't treat you safely without your history.</code> | Task catalog MEDICAL_RECORDS — whyNeeded |
| 862 | <code>Banks, cards, brokerages, loans — one pass updates every address so autopay and statements never miss.</code> | Task catalog FINANCIAL_ACCOUNTS — desc |
| 865 | <code>Update before your next statement closes — mismatches trigger fraud alerts.</code> | Task catalog FINANCIAL_ACCOUNTS — tips |
| 867 | <code>Outdated info triggers fraud alerts and frozen cards on day one.</code> | Task catalog FINANCIAL_ACCOUNTS — whyNeeded |
| 897 | <code>Gyms, studios, spas, clubs — cancellations and transfers need 30-day notices. One pass, all of them.</code> | Task catalog MEMBERSHIPS — desc |
| 900 | <code>Check your membership terms — some require 30 days written notice.</code> | Task catalog MEMBERSHIPS — tips |
| 902 | <code>Miss a notice window and you pay for a gym you can't visit.</code> | Task catalog MEMBERSHIPS — whyNeeded |
| 929 | <code>We'll find units near your new place with real availability and move-in specials before move day.</code> | Task catalog STORAGE_UNIT — desc |
| 932 | <code>Book two weeks out — first-month-free deals go to early reservations.</code> | Task catalog STORAGE_UNIT — tips |
| 934 | <code>Sold-out units near the new place mean storing across town.</code> | Task catalog STORAGE_UNIT — whyNeeded |
| 949 | <code>Your plan is waiting on the destination. Add it and everything downstream unlocks.</code> | Task catalog ADD_NEW_ADDRESS — desc |
| 952 | <code>A street address beats a city — distance and deadlines get exact.</code> | Task catalog ADD_NEW_ADDRESS — tips |
| 954 | <code>Distance, deadlines, and half your tasks depend on where you're headed.</code> | Task catalog ADD_NEW_ADDRESS — whyNeeded |
| 969 | <code>You marked the date flexible. Lock it in — or confirm the estimate — so the plan paces itself right.</code> | Task catalog CONFIRM_MOVE_DATE — desc |
| 972 | <code>Mid-month weekdays book cheaper movers than month-end weekends.</code> | Task catalog CONFIRM_MOVE_DATE — tips |
| 974 | <code>Every deadline on your plan counts backward from this date.</code> | Task catalog CONFIRM_MOVE_DATE — whyNeeded |
| 990 | <code>One tap: planning to sell or donate before the move? We'll line up the right help.</code> | Task catalog DECLUTTER_INTENT — desc |
| 993 | <code>Every unsold item becomes a box you pay to move.</code> | Task catalog DECLUTTER_INTENT — tips |
| 995 | <code>Selling and donating both need lead time — the earlier we know, the more it pays.</code> | Task catalog DECLUTTER_INTENT — whyNeeded |
| 1011 | <code>Will everything fit — or might you need a unit? One tap and we'll handle the rest.</code> | Task catalog STORAGE_NEED — desc |
| 1014 | <code>Units near new builds sell out first — early answers get options.</code> | Task catalog STORAGE_NEED — tips |
| 1016 | <code>Storage found on move day costs double and sits across town.</code> | Task catalog STORAGE_NEED — whyNeeded |
| 1029 | <code>Four factual questions help Peezy hold moving partners accountable and improve the experience for everyone.</code> | Task catalog MOVE_CHECKIN — desc |
| 1032 | <code>Stick to what happened — arrival, pace, price, and damage.</code> | Task catalog MOVE_CHECKIN — tips |
| 1034 | <code>Fresh facts are how good vendors earn trust and bad behavior gets addressed.</code> | Task catalog MOVE_CHECKIN — whyNeeded |
| 1047 | <code>Count the boxes leaving your home so Peezy can tune future kits and help arrange pickup if you want it.</code> | Task catalog BOX_RETURN — desc |
| 1050 | <code>Flatten clean boxes before recycling or pickup.</code> | Task catalog BOX_RETURN — tips |
| 1052 | <code>Returned counts reduce waste and make the next kit estimate sharper.</code> | Task catalog BOX_RETURN — whyNeeded |
