import Foundation

struct Template: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var plan: Plan
}
