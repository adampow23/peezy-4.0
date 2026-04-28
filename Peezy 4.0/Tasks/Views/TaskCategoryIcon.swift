import Foundation

enum TaskCategoryIcon {
    static func name(for category: String?) -> String {
        switch (category ?? "").lowercased() {
        case "moving":          return "shippingbox.fill"
        case "packing":         return "archivebox.fill"
        case "services":        return "wrench.and.screwdriver.fill"
        case "utilities":       return "bolt.fill"
        case "administrative":  return "doc.text.fill"
        case "children":        return "figure.and.child.holdinghands"
        case "pets":            return "pawprint.fill"
        case "finance":         return "creditcard.fill"
        case "insurance":       return "shield.checkered"
        case "health":          return "heart.fill"
        case "fitness":         return "figure.run"
        default:                return "checklist"
        }
    }
}
