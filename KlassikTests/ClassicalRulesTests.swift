import Testing

@testable import Klassik

struct ClassicalRulesTests {
    /// The result rows say how much of the server library the rules let through.
    @Test func resultNamesThePartOfTheServer() {
        #expect(ClassicalRulesView.share(3, of: 5) == "3 of 5 on server")
        #expect(ClassicalRulesView.share(0, of: 0) == "0 of 0 on server")
    }
}
